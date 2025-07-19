
document.addEventListener("DOMContentLoaded", () => {
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

    const myButton = document.getElementById("myButton");
    const messageArea = document.getElementById("messageArea");

    if (myButton) {
        myButton.addEventListener("click", () => {
            messageArea.textContent = "Button worked";

        });
    }
});