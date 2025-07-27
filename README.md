# Cockpit Plugin Toolkit

This toolkit provides a set of scripts to simplify the creation, local development, and distribution of Cockpit plugins via the Open Build Service (OBS).

## Overview

The workflow is broken down into two main steps:

1.  **`initialize.sh`**: Scaffolds a new plugin directory from a template, setting up the basic file structure and replacing placeholder values.
2.  **`share.sh`**: Creates a project and package on the Open Build Service (OBS), generates a `.spec` file, and uploads your plugin files to be built into an RPM.

## Prerequisites

Before you begin, you will need:

1.  **The `osc` command-line tool**: This is used to interact with OBS.
    ```bash
    sudo zypper install osc
    ```

2.  **An Open Build Service (OBS) Account**: You can register for free at build.opensuse.org.

## Usage

Follow these steps to create and distribute your plugin.

### Step 1: Initialize Your Plugin

Run the `initialize.sh` script from the root of the toolkit directory, providing a name for your new plugin. Plugin names should be lowercase and can use hyphens.

```bash
# Example: Create a plugin named 'hello-world'
./scripts/initialize.sh hello-world
```

The script will create a new directory (`hello-world/`) containing all the necessary files from the template.

#### Local Development

To test your plugin locally as you develop, the `initialize.sh` script automatically creates a symbolic link from your new plugin directory to your user's local Cockpit directory (`~/.local/share/cockpit`). This allows you to see your changes in Cockpit without needing `sudo` for the initial setup.

After the link is created, you can start developing. If you make changes and don't see them reflected, you may need to restart the Cockpit service:
```bash
sudo systemctl restart cockpit.socket
```
You can then log into Cockpit (usually at `https://localhost:9090`) to see your plugin in action.

### Step 2: Develop Your Plugin

Navigate into your new plugin directory and start developing!

```bash
cd hello-world/
```

Modify the `index.html`, `script.js`, and `style.css` files to build your plugin's functionality and appearance.

### Step 3: Share Your Plugin on OBS

Once you are ready to create a distributable RPM package, run the `share.sh` script from the root of the toolkit directory.

```bash
# This will package the 'hello-world' plugin
./scripts/share.sh hello-world
```

**First-Time Setup**: The first time you run this script, it will detect if your `~/.oscrc` file is configured. If not, it will create a template for you. You will need to edit this file with your OBS username and password (or preferably, a token generated from your OBS profile page).

The script will then:
1.  Create a new project in your OBS home directory (e.g., `home:your-user:hello-world`).
2.  Create a package within that project (e.g., `cockpit-hello-world`).
3.  Generate a `.spec` file for building the RPM.
4.  Commit and upload all your plugin files to OBS.
5.  Trigger a build.

You can monitor the build progress at the URL provided by the script.

### Step 4: Install Your Packaged Plugin

Once the build status on the OBS website shows **"succeeded"**, you can install the RPM on any target openSUSE Tumbleweed system.

1.  **Add your OBS repository:**
    ```bash
    # Replace 'your-user' and 'hello-world' with your details
    sudo zypper ar https://download.opensuse.org/repositories/home:/your-user:/hello-world/openSUSE_Tumbleweed/home:your-user:hello-world.repo
    ```

2.  **Refresh and install:**
    You will be prompted to trust the GPG key for the new repository. This is expected.
    ```bash
    sudo zypper ref
    sudo zypper in cockpit-hello-world
    ```