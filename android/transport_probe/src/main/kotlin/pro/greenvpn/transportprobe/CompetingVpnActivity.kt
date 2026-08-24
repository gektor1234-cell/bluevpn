package pro.greenvpn.transportprobe

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import androidx.core.content.ContextCompat

class CompetingVpnActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.getStringExtra(EXTRA_ACTION) == ACTION_STOP) {
            startService(
                Intent(this, CompetingVpnService::class.java)
                    .setAction(CompetingVpnService.ACTION_STOP),
            )
            finish()
            return
        }

        val permissionIntent = VpnService.prepare(this)
        if (permissionIntent == null) {
            startProbeVpn()
        } else {
            startActivityForResult(permissionIntent, VPN_PERMISSION_REQUEST)
        }
    }

    @Deprecated("Deprecated by Android, retained for the test-only VPN consent flow")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_REQUEST && resultCode == RESULT_OK) {
            startProbeVpn()
        } else {
            finish()
        }
    }

    private fun startProbeVpn() {
        ContextCompat.startForegroundService(
            this,
            Intent(this, CompetingVpnService::class.java),
        )
        finish()
    }

    companion object {
        const val EXTRA_ACTION = "action"
        const val ACTION_STOP = "stop"
        private const val VPN_PERMISSION_REQUEST = 41
    }
}
