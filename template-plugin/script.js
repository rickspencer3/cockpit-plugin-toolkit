// Import the Cockpit API
import { cockpit } from "/cockpit/base1.js";

// Wait for the DOM to be fully loaded
document.addEventListener("DOMContentLoaded", () => {
    console.log("Template Plugin: DOMContentLoaded");

    // Get the button and message area elements
    const myButton = document.getElementById("myButton");
    const messageArea = document.getElementById("messageArea");

    // Add a click event listener to the button
    if (myButton) {
        myButton.addEventListener("click", () => {
            messageArea.textContent = cockpit.get  text("button-clicked-message");
        });
    }

    // Example of using translations for elements with data-i18n attribute
    document.querySelectorAll("[data-i18n]").forEach(element => {
        const key = element.getAttribute("data-i18n");
        element.textContent = cockpit.get  text(key);
    });

    // You can add more plugin-specific logic here
});

// Example of a simple function for later use
function sayHello() {
    console.log("Hello from Template Plugin!");
}