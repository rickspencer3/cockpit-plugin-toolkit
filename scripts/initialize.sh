#!/bin/bash

# This script creates a new directory with the specified plugin name
# and copies the contents of the 'template-plugin' directory into it.
# It requires the plugin name to be passed as an argument.

# Function to display error messages and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Ensure plugin name is provided as an argument
if [ -z "$1" ]; then
    error_exit "Usage: ./scripts/initialize.sh <new-plugin-name>"
fi

NEW_PLUGIN_NAME="$1"

# Validate the plugin name
# Allowed characters: lowercase alphanumeric, hyphens, underscores. Must not start/end with hyphen/underscore.
if [[ ! "$NEW_PLUGIN_NAME" =~ ^[a-z0-9]+([-_][a-z0-9]+)*$ ]]; then
    error_exit "Invalid plugin name. Please use lowercase alphanumeric characters, hyphens, or underscores. It cannot start or end with a hyphen/underscore, or have consecutive hyphens/underscores. Example: my-awesome-plugin"
fi

# Define the old and new names for replacement
OLD_PLUGIN_ID="TEMPLATE_PLUGIN_ID"
OLD_PLUGIN_LABEL="Template Plugin Name"

# Convert plugin name to a more readable label (e.g., my-awesome-plugin -> My Awesome Plugin)
NEW_PLUGIN_LABEL=$(echo "$NEW_PLUGIN_NAME" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')

echo "Initializing new plugin: $NEW_PLUGIN_NAME"
echo "Plugin label will be: $NEW_PLUGIN_LABEL"

# Determine the root directory of the toolkit (where 'scripts' and 'template-plugin' reside)
# This makes the script robust to being run from different current working directories
TOOLKIT_ROOT_DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"

# Define path to the template directory relative to the toolkit's root
TEMPLATE_DIR="$TOOLKIT_ROOT_DIR/template-plugin"
# Define the path for the new plugin directory relative to the current working directory
NEW_PLUGIN_DIR_PATH="$NEW_PLUGIN_NAME"

echo "Preparing new plugin directory: $NEW_PLUGIN_DIR_PATH (in current working directory)"

# Check if the target plugin directory already exists in the current working directory
if [ -d "$NEW_PLUGIN_DIR_PATH" ]; then
    error_exit "A directory named '$NEW_PLUGIN_NAME' already exists in the current directory. Please choose a different name or remove the existing directory."
fi

# Check if the template directory exists
if [ ! -d "$TEMPLATE_DIR" ]; then
    error_exit "Template directory '$TEMPLATE_DIR' not found. Please ensure 'template-plugin' exists in the toolkit's root."
fi

# Create the new directory in the current working directory
echo "Creating directory '$NEW_PLUGIN_DIR_PATH'..."
mkdir -p "$NEW_PLUGIN_DIR_PATH" || error_exit "Failed to create directory '$NEW_PLUGIN_DIR_PATH'."

# Copy the template directory contents into the new plugin directory
echo "Copying contents from '$TEMPLATE_DIR' to '$NEW_PLUGIN_DIR_PATH'..."
cp -R "$TEMPLATE_DIR"/* "$NEW_PLUGIN_DIR_PATH/" || error_exit "Failed to copy template contents."

echo "New plugin directory '$NEW_PLUGIN_NAME' created and populated successfully at '$PWD/$NEW_PLUGIN_NAME'."

# --- Add Step: Replace placeholders in files ---
echo "Replacing placeholders in plugin files within '$NEW_PLUGIN_DIR_PATH'..."

# List of files to modify (relative to the new plugin directory)
FILES_TO_MODIFY=(
    "manifest.json"
    "index.html"
    "script.js"
    "style.css"
)

# Iterate through files and perform replacements
for file in "${FILES_TO_MODIFY[@]}"; do
    FILE_PATH="$NEW_PLUGIN_DIR_PATH/$file"
    if [ -f "$FILE_PATH" ]; then
        echo "  - Processing $FILE_PATH"
        # Use sed for in-place replacement. Use a temporary file for safety.
        # macOS sed requires a backup extension (e.g., '')
        sed -i.bak "s/$OLD_PLUGIN_ID/$NEW_PLUGIN_NAME/g" "$FILE_PATH"
        sed -i.bak "s/$OLD_PLUGIN_LABEL/$NEW_PLUGIN_LABEL/g" "$FILE_PATH"
        rm "${FILE_PATH}.bak" # Remove the backup file
    else
        echo "  - Warning: File not found: $FILE_PATH"
    fi
done

echo "Placeholders replaced successfully."

# --- Final Step: Link the plugin to Cockpit ---
echo ""
echo "--- Final Step: Linking the plugin for local development ---"

# Define Cockpit's plugin directory and the source/target paths
COCKPIT_PLUGINS_DIR="$HOME/.local/share/cockpit"
SOURCE_DIR="$PWD/$NEW_PLUGIN_DIR_PATH"
SYMLINK_TARGET="$COCKPIT_PLUGINS_DIR/$NEW_PLUGIN_NAME"

echo "To make the plugin visible in Cockpit for local development, a symbolic link"
echo "will be created in your user's local Cockpit directory: $COCKPIT_PLUGINS_DIR"

# Ensure the local Cockpit plugin directory exists
mkdir -p "$COCKPIT_PLUGINS_DIR"

echo "Creating symbolic link: $SYMLINK_TARGET"
ln -s "$SOURCE_DIR" "$SYMLINK_TARGET"

echo ""
echo "Symbolic link created successfully!"
echo ""
echo "You can now start developing. After making changes, you may need to restart"
echo "the Cockpit service to see them reflected:"
echo ""
echo "  sudo systemctl restart cockpit.socket"
echo ""
echo "Then, log into Cockpit (usually at https://localhost:9090) to see your plugin."
echo ""
echo "Initialization complete for '$NEW_PLUGIN_NAME'!"
