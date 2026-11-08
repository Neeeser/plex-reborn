# Machine and account settings used by the project scripts.
# Copy this file to config.local.sh and fill it in. config.local.sh is
# ignored by Git, so device IDs and account IDs never reach the repository.

# The phone to install on. List connected devices with:
#   xcrun devicectl list devices
DEVICE_UDID=""

# The iPhone Duo simulator to test in. List simulators with:
#   xcrun simctl list devices | grep -i duo
SIM_UDID=""

# Your Apple developer team ID (10 characters). Find it with:
#   security find-identity -v -p codesigning
# or in the Membership page of developer.apple.com.
TEAM_ID=""

# Reverse-DNS prefix for bundle IDs of apps you sign yourself, for example
# com.yourname. Keep the app's brand name out of it.
BUNDLE_PREFIX=""
