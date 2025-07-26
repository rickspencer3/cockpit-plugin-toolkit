#!/bin/bash

# This script handles the first step of sharing a Cockpit plugin on the Open
# Build Service (OBS): creating a package in your home project.

# Function to display error messages and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# --- 1. Check for dependencies ---
if ! command -v osc &> /dev/null; then
    error_exit "The 'osc' command-line tool is not installed. Please install it to continue.
sudo zypper install osc"
fi

# --- 2. Get user and plugin details ---
if [ -z "$1" ]; then
    error_exit "Usage: ./scripts/share.sh <plugin-name> [obs-api-url]"
fi

PLUGIN_NAME="$1"

# Verify the plugin directory exists in the current path
if [ ! -d "$PLUGIN_NAME" ]; then
    error_exit "Plugin directory '$PLUGIN_NAME' not found in the current directory.
Please run this script from the same directory where you ran initialize.sh."
fi

# --- 3. Check for and verify OBS credentials ---
OSCRC_FILE="$HOME/.oscrc"

# Determine the OBS API URL. Priority is as follows:
# 1. Command-line argument ($2).
# 2. The 'apiurl' setting in the [general] section of ~/.oscrc.
# 3. A fallback default value.
OBS_API_URL=""
DEFAULT_OBS_API_URL="https://api.opensuse.org"

if [ -n "$2" ]; then
    OBS_API_URL="$2"
    echo "Using API URL from command-line argument: $OBS_API_URL"
elif [ -f "$OSCRC_FILE" ]; then
    # Attempt to parse the apiurl from the [general] section of .oscrc
    # This handles lines like 'apiurl = https://...' and trims whitespace.
    # 'cut -d'=' -f2-' handles URLs that might contain an '=' character.
    PARSED_URL=$(grep -E '^\s*apiurl\s*=' "$OSCRC_FILE" | tail -n 1 | cut -d'=' -f2- | xargs)
    if [ -n "$PARSED_URL" ]; then
        OBS_API_URL="$PARSED_URL"
        echo "Using API URL from your $OSCRC_FILE configuration: $OBS_API_URL"
    fi
fi

# If no URL was found from the above methods, use the default.
if [ -z "$OBS_API_URL" ]; then
    OBS_API_URL="$DEFAULT_OBS_API_URL"
    echo "No API URL specified or found in config, using default: $OBS_API_URL"
fi

# Check if the .oscrc file exists. If not, create a template and exit with instructions.
if [ ! -f "$OSCRC_FILE" ]; then
    echo "OBS configuration file not found at '$OSCRC_FILE'."
    echo "Creating a template file for you..."

    # Create a template .oscrc file using the specified API URL
    cat > "$OSCRC_FILE" <<- EOF
[general]
apiurl = $OBS_API_URL

[$OBS_API_URL]
user = YOUR_OBS_USERNAME_HERE
pass = YOUR_OBS_PASSWORD_OR_TOKEN_HERE
EOF
    # Set secure permissions for the file as it contains credentials
    chmod 600 "$OSCRC_FILE"

    error_exit "Template '$OSCRC_FILE' created.
Please edit this file with your Open Build Service username and password/token.
You can generate a token from your OBS profile page for better security.
Re-run this script after you have configured the file."
fi

echo "Found OBS configuration at '$OSCRC_FILE'. Verifying connection..."
# Use 'whois' for compatibility with older osc versions, and 'head -n 1' to get just the username.
# The 'whois' command can return 'username: Real Name <email>'. We only want the username part.
OBS_USER=$(osc -A "$OBS_API_URL" whois 2>/dev/null | head -n 1 | cut -d':' -f1 | xargs)

if [ -z "$OBS_USER" ]; then
    error_exit "Could not determine your OBS username using the credentials in '$OSCRC_FILE'.
Please make sure your username and password/token are correct in that file.
Run 'osc -A $OBS_API_URL whois' to test your connection."
fi

echo "Successfully authenticated as OBS user: $OBS_USER"

# --- 4. Define project and package names ---
PLUGIN_PROJECT="home:$OBS_USER:$PLUGIN_NAME"
PACKAGE_NAME="cockpit-$PLUGIN_NAME"
PROJECT_URL="${OBS_API_URL/api/build}/project/show/$PLUGIN_PROJECT"

echo "Using OBS project: $PLUGIN_PROJECT"

# --- 5. Check for and create the OBS project if it doesn't exist ---
echo "Checking if project exists..."
if ! osc -A "$OBS_API_URL" meta prj "$PLUGIN_PROJECT" &> /dev/null; then
    echo "Project '$PLUGIN_PROJECT' does not exist. Creating it now..."

    # Create a temporary file for the project metadata
    PROJECT_META_FILE=$(mktemp)
    # Use a trap to ensure the temporary file is deleted on exit
    trap 'rm -f "$PROJECT_META_FILE"' EXIT

    # Create the project metadata XML content.
    # The <url> tag is a placeholder for the user to fill in.
    # A default build target for openSUSE Tumbleweed is included.
    cat > "$PROJECT_META_FILE" <<- EOF
<project name="$PLUGIN_PROJECT">
  <title>Cockpit Plugin: $PLUGIN_NAME</title>
  <description>An OBS project for the $PLUGIN_NAME Cockpit plugin.</description>
  <url>https://github.com/YOUR_USERNAME/$PLUGIN_NAME</url>
  <repository name="openSUSE_Tumbleweed">
    <path project="openSUSE:Factory" repository="snapshot"/>
    <arch>x86_64</arch>
  </repository>
</project>
EOF

    # Use 'osc api' to create the project using the metadata file.
    # The path must end in '_meta' to update project metadata.
    if osc -A "$OBS_API_URL" api -X PUT "/source/$PLUGIN_PROJECT/_meta" -f "$PROJECT_META_FILE"; then
        echo "Successfully created OBS project: $PLUGIN_PROJECT"
        echo "You can view it at: $PROJECT_URL"
    else
        # Clean up and exit on failure
        rm -f "$PROJECT_META_FILE"
        error_exit "Failed to create OBS project '$PLUGIN_PROJECT'."
    fi
    # The trap will clean up the file on successful exit
else
    echo "Project '$PLUGIN_PROJECT' already exists."
fi

# --- 6. Check for and create the package within the project ---
echo "Checking for existing OBS package '$PACKAGE_NAME' in project '$PLUGIN_PROJECT'..."

if osc -A "$OBS_API_URL" ls "$PLUGIN_PROJECT" "$PACKAGE_NAME" &> /dev/null; then
    echo "Package '$PACKAGE_NAME' already exists in '$PLUGIN_PROJECT'. No action needed."
    echo "To work with it, run: osc -A \"$OBS_API_URL\" co \"$PLUGIN_PROJECT\" \"$PACKAGE_NAME\""
    exit 0
fi

# --- 7. Create the package ---
echo "Package does not exist. Creating it now..."

# The 'osc mkpac' command can be unreliable in scripts depending on the osc version,
# sometimes causing a 'Wrong number of arguments' error as you observed.
# A more robust method is to explicitly create the package metadata and use 'osc meta pkg'.
PACKAGE_META_FILE=$(mktemp)

# Convert plugin name to a more readable label for the title (e.g., local-network -> Local Network)
PACKAGE_TITLE=$(echo "$PLUGIN_NAME" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')

cat > "$PACKAGE_META_FILE" <<- EOF
<package name="$PACKAGE_NAME" project="$PLUGIN_PROJECT">
  <title>Cockpit Plugin: $PACKAGE_TITLE</title>
  <description>RPM package for the $PLUGIN_NAME Cockpit plugin.</description>
</package>
EOF

# Use 'osc meta pkg' to create the package using the metadata file.
if osc -A "$OBS_API_URL" meta pkg -F "$PACKAGE_META_FILE" "$PLUGIN_PROJECT" "$PACKAGE_NAME"; then
    # Clean up the temporary file on success
    rm -f "$PACKAGE_META_FILE"

    PACKAGE_URL="${OBS_API_URL/api/build}/package/show/$PLUGIN_PROJECT/$PACKAGE_NAME"
    echo "Successfully created OBS package: $PACKAGE_NAME in project $PLUGIN_PROJECT"
    echo "You can view it at: $PACKAGE_URL"
    echo ""
    echo "--- Next Steps ---"
    echo "To add your plugin files to the project, run the following commands:"
    echo ""
    echo "  # Check out your new package directory from OBS"
    echo "  osc -A \"$OBS_API_URL\" co \"$PLUGIN_PROJECT\" \"$PACKAGE_NAME\""
    echo ""
    echo "  # Copy your plugin files into it (assuming you are in the parent directory)"
    echo "  cp -r \"$PLUGIN_NAME/\"* \"$PACKAGE_NAME/\""
    echo ""
    echo "  # Enter the directory, add the files, and commit them to OBS"
    echo "  cd \"$PACKAGE_NAME\""
    echo "  osc add *"
    echo "  osc commit -m \"Initial import of $PLUGIN_NAME\""
    echo ""
    echo "You will also need to create a .spec file to define how to build the RPM package."
else
    # Clean up the temporary file on failure
    rm -f "$PACKAGE_META_FILE"
    error_exit "Failed to create OBS package '$PACKAGE_NAME' in project '$PLUGIN_PROJECT'."
fi