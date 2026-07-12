package hev.htproxy

class TProxyService {
    companion object {
        init {
            System.loadLibrary("hev-socks5-tunnel")
        }
    }

    external fun TProxyStartService(configPath: String, tunFd: Int)
    external fun TProxyStopService()
    external fun TProxyGetStats(): LongArray
}
