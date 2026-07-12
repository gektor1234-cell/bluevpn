package pro.greenvpn.vless

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import java.io.File

class VlessRealityPermissionDebugActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val permission = VpnService.prepare(this)
        if (permission == null) {
            writeResult("granted")
            finish()
        } else {
            startActivityForResult(permission, REQUEST_VPN)
        }
    }

    @Deprecated("Debug-only compatibility with the Android VPN permission flow")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN) {
            writeResult(if (resultCode == RESULT_OK) "granted" else "denied")
            finish()
        }
    }

    private fun writeResult(value: String) {
        File(filesDir, RESULT_NAME).writeText(value + "\n", Charsets.UTF_8)
    }

    companion object {
        const val RESULT_NAME = "greenvpn-vless-permission-result.txt"
        private const val REQUEST_VPN = 8843
    }
}
