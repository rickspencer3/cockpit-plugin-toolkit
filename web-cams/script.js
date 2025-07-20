
document.addEventListener("DOMContentLoaded", () => {
    initializeWebcamView();
});

async function initializeWebcamView() {
    const container = document.getElementById("webcam-container");
    const statusMessage = document.getElementById("status-message");

    if (!container || !statusMessage) {
        console.error("Required HTML elements not found.");
        return;
    }

    if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) {
        statusMessage.textContent = "Webcam API is not supported by this browser.";
        return;
    }

    try {
        // First, get the list of system video devices from the OS.
        // We'll correlate this with the browser's device list.
        let systemDevicePaths = [];
        try {
            // Use cockpit.spawn to run a shell command to list video devices
            // We use 'sh -c' to ensure the wildcard '*' is expanded by the shell.
            const ls_output = await cockpit.spawn(["sh", "-c", "ls -d /dev/video*"], { "err": "message" });
            // The output is a newline-separated string. We split it into an array.
            systemDevicePaths = ls_output.trim().split('\n').filter(p => p);
        } catch (err) {
            // This can fail if no devices exist. We'll just show a warning in the console.
            console.warn("Could not list /dev/video* devices. System info will not be available.", err);
        }

        // We must request permission first to get device labels for security reasons.
        // This triggers the browser's permission prompt.
        const permissionStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });

        const devices = await navigator.mediaDevices.enumerateDevices();
        const videoDevices = devices.filter(device => device.kind === 'videoinput');

        // We have the labels, so we can stop the temporary stream used for permission.
        permissionStream.getTracks().forEach(track => track.stop());

        if (videoDevices.length === 0) {
            statusMessage.textContent = "No webcams found.";
            return;
        }

        // Hide status message if we found cameras
        statusMessage.style.display = 'none';

        videoDevices.forEach((device, index) => {
            // We assume the order of devices from the browser matches the system's /dev/video* order.
            const systemPath = systemDevicePaths[index] || null;
            createWebcamCard(device, container, systemPath);
        });

    } catch (err) {
        console.error("Error accessing webcams: ", err);
        statusMessage.textContent = `Error accessing webcams: ${err.name}. Please ensure you have granted permission in your browser.`;
    }
}

async function createWebcamCard(device, container, systemDevicePath) {
    const card = document.createElement('div');
    card.className = 'webcam-card';

    const label = document.createElement('div');
    label.className = 'label';
    label.textContent = device.label || `Camera ${container.children.length + 1}`;
    card.appendChild(label);

    const video = document.createElement('video');
    video.autoplay = true;
    video.playsInline = true; // Important for mobile browsers
    card.appendChild(video);

    // Add a container for system-level info if we have a path
    if (systemDevicePath) {
        const systemInfoContainer = document.createElement('div');
        systemInfoContainer.className = 'system-info';
        systemInfoContainer.innerHTML = `<h4>System Capabilities (${systemDevicePath})</h4><p>Loading...</p>`;
        card.appendChild(systemInfoContainer);
        displaySystemInfo(systemDevicePath, systemInfoContainer);
    }

    container.appendChild(card);

    try {
        const constraints = {
            video: {
                deviceId: { exact: device.deviceId },
                width: { ideal: 1920 },
                height: { ideal: 1080 }
            }
        };

        const stream = await navigator.mediaDevices.getUserMedia(constraints);
        video.srcObject = stream;

        video.onloadedmetadata = () => {
            const track = stream.getVideoTracks()[0];
            if (!track) return;

            const settings = track.getSettings();
            const infoContainer = document.createElement('div');
            infoContainer.className = 'webcam-info';

            let infoHtml = '<ul>';
            if (settings.width && settings.height) {
                infoHtml += `<li><strong>Resolution:</strong> ${settings.width}x${settings.height}</li>`;
            }
            if (settings.frameRate) {
                infoHtml += `<li><strong>Frame Rate:</strong> ${settings.frameRate} fps</li>`;
            }
            if (settings.aspectRatio) {
                infoHtml += `<li><strong>Aspect Ratio:</strong> ${settings.aspectRatio.toFixed(2)}</li>`;
            }
            if (settings.facingMode && settings.facingMode !== 'unknown') {
                infoHtml += `<li><strong>Facing Mode:</strong> ${settings.facingMode}</li>`;
            }
            infoHtml += '</ul>';

            infoContainer.innerHTML = infoHtml;
            card.appendChild(infoContainer);
        };
    } catch (err) {
        console.error(`Error starting video for ${device.label}:`, err);
        label.textContent += " (Error starting stream)";
        card.classList.add('error');
    }
}

/**
 * Parses the text output of `v4l2-ctl --list-formats-ext` into a structured object.
 * @param {string} output - The raw string output from the command.
 * @returns {object} A structured object of capabilities.
 */
function parseV4l2Output(output) {
    const lines = output.split('\n');
    const formats = {};
    let currentFormat = null;
    let currentSize = null;

    // A more robust parser to handle variations in v4l2-ctl output across different drivers.
    // It looks for more patterns and is less dependent on strict line formatting.
    const formatRegex = /(?:Pixel Format|\[\d+\]):\s+'?(\w+)'?/;
    const sizeRegex = /Size:\s*(?:\w+\s+)?([0-9]+x[0-9]+)/;
    const intervalRegex = /Interval:.*\((\d+(?:\.\d+)?)\s+fps\)/;

    for (const line of lines) {
        const formatMatch = line.match(formatRegex);
        if (formatMatch) {
            // We found a new format section.
            currentFormat = formatMatch[1];
            if (!formats[currentFormat]) {
                formats[currentFormat] = {};
            }
            // Reset the current size, as it belongs to the previous format.
            currentSize = null;
            continue; // Move to the next line
        }

        const sizeMatch = line.match(sizeRegex);
        if (currentFormat && sizeMatch) {
            // We found a new size for the current format.
            currentSize = sizeMatch[1];
            if (!formats[currentFormat][currentSize]) {
                formats[currentFormat][currentSize] = [];
            }
            continue; // Move to the next line
        }

        const intervalMatch = line.match(intervalRegex);
        if (currentFormat && currentSize && intervalMatch) {
            // We found a frame rate for the current format and size.
            const fps = parseFloat(intervalMatch[1]);
            if (!isNaN(fps)) {
                formats[currentFormat][currentSize].push(fps);
            }
        }
    }
    return formats;
}

/**
 * Fetches and displays system-level device info using v4l2-ctl.
 * @param {string} devicePath - The system path, e.g., /dev/video0.
 * @param {HTMLElement} container - The DOM element to inject the info into.
 */
async function displaySystemInfo(devicePath, container) {
    try {
        const output = await cockpit.spawn(["v4l2-ctl", "--list-formats-ext", "-d", devicePath], { "err": "message", "superuser": "require" });
        const capabilities = parseV4l2Output(output);
        let html = `<h4>System Capabilities (${devicePath})</h4>`;

        // Check if the parser found any capabilities before trying to display them.
        if (Object.keys(capabilities).length > 0) {
            html += '<div class="capability-list">';
            for (const format in capabilities) {
                html += `<div class="format-section"><strong>${format}</strong><ul>`;
                for (const size in capabilities[format]) {
                    const fpsList = capabilities[format][size].sort((a, b) => b - a).join(', ');
                    html += `<li>${size} @ ${fpsList} fps</li>`;
                }
                html += '</ul></div>';
            }
            html += '</div>';
        } else {
            // Display a helpful message if no capabilities were found.
            html += '<p>No detailed capabilities could be retrieved for this device.</p>';
        }
        container.innerHTML = html;

        // Add a container and button for showing the full, raw v4l2-ctl output
        const detailsContainer = document.createElement('div');
        detailsContainer.className = 'full-details-container';

        const detailsButton = document.createElement('button');
        detailsButton.className = 'details-button';
        detailsButton.textContent = 'Show Full Details';
        detailsButton.type = 'button';

        const detailsPre = document.createElement('pre');
        detailsPre.className = 'full-details-output';
        detailsPre.style.display = 'none'; // Initially hidden

        detailsContainer.appendChild(detailsButton);
        detailsContainer.appendChild(detailsPre);
        container.appendChild(detailsContainer);

        // When the button is clicked, run `v4l2-ctl --all` and display the output
        detailsButton.addEventListener('click', async () => {
            const isHidden = detailsPre.style.display === 'none';
            if (isHidden) {
                // Fetch details only once
                if (!detailsPre.textContent) {
                    detailsButton.disabled = true;
                    detailsButton.textContent = 'Loading...';
                    try {
                        const fullOutput = await cockpit.spawn(["v4l2-ctl", "-d", devicePath, "--all"], { "err": "message", "superuser": "require" });
                        detailsPre.textContent = fullOutput;
                    } catch (err) {
                        detailsPre.textContent = `Error fetching full details for ${devicePath}:\n${err.message}`;
                        detailsPre.classList.add('error-text');
                    } finally {
                        detailsButton.disabled = false;
                    }
                }
                detailsPre.style.display = 'block';
                detailsButton.textContent = 'Hide Full Details';
            } else {
                detailsPre.style.display = 'none';
                detailsButton.textContent = 'Show Full Details';
            }
        });
    } catch (err) {
        console.error(`Failed to get v4l2-ctl info for ${devicePath}:`, err);
        container.innerHTML = `<h4>System Capabilities (${devicePath})</h4><p class="error-text">Could not run v4l2-ctl. Is it installed? (Error: ${err.message})</p>`;
    }
}