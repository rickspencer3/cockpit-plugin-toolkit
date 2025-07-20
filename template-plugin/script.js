
document.addEventListener("DOMContentLoaded", () => {
    // Boiler plate for plugin authors, safe to remove
    test_cockpit_api();
    set_up_sample_ui();
});

function set_up_sample_ui(){
    const myButton = document.getElementById("myButton");
    const messageArea = document.getElementById("messageArea");

    if (myButton) {
        myButton.addEventListener("click", () => {
            messageArea.textContent = cockpit.gettext("Button Clicked");
        });
    } else {
        console.error("Button not found");
    }
}

function test_cockpit_api() {
    console.log("My Cool Plugin: DOMContentLoaded");
    console.log("Tesing the cockpit API.");
    console.log("Running a uname -a:")

    cockpit.spawn(["uname", "-a"])
    .stream(data => {
        console.log("Successfully tested cockpit.spawn()");
        console.log(data);
    })
    .catch(err => {
        console.error("Command failed", err);
    });
}