package pro.greenvpn.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle

class VpnConsentDebugActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val permissionIntent = VpnService.prepare(this)
        if (permissionIntent == null) {
            finish()
        } else {
            startActivityForResult(permissionIntent, VPN_PERMISSION_REQUEST)
        }
    }

    @Deprecated("Retained for the test-only VPN consent flow")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        finish()
    }

    private companion object {
        const val VPN_PERMISSION_REQUEST = 73
    }
}
