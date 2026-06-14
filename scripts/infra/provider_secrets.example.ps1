# Copy this file to D:\GreenVPN_Secrets\provider_api.local.ps1 and fill real values there.
# Do not commit the real local file. Runtime scripts load D:\GreenVPN_Secrets first.

$env:GREENVPN_SERVERSPACE_API_KEY = "CHANGE_ME"
$env:GREENVPN_TIMEWEB_TOKEN = "CHANGE_ME"
$env:GREENVPN_RUVDS_API_KEY = "CHANGE_ME"
$env:GREENVPN_RUVDS_API_LOGIN = "CHANGE_ME"
$env:GREENVPN_RUVDS_API_PASSWORD = "CHANGE_ME"
$env:GREENVPN_HOSTKEY_API_KEY = "CHANGE_ME"

# Optional for backend draft registration from local scripts.
$env:BLUEVPN_ADMIN_TOKEN = "CHANGE_ME"
