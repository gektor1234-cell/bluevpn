using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

internal static class GreenVpnInstallerBootstrap
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool DeleteFile(string fileName);

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static void RemoveInternetZone(string path)
    {
        if (!File.Exists(path))
        {
            return;
        }

        DeleteFile(path + ":Zone.Identifier");
    }

    private static void WriteFailureLog(Exception exception)
    {
        try
        {
            string logPath = Path.Combine(Path.GetTempPath(), "GreenVPN_Setup_bootstrap.log");
            File.WriteAllText(
                logPath,
                DateTime.UtcNow.ToString("O") + Environment.NewLine +
                exception.GetType().FullName + ": " + exception.Message + Environment.NewLine,
                Encoding.UTF8);
        }
        catch
        {
        }
    }

    [STAThread]
    private static int Main()
    {
        try
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string uiScript = Path.Combine(root, "install_ui.ps1");
            string installScript = Path.Combine(root, "install_greenvpn.ps1");
            string payloadZip = Path.Combine(root, "GreenVPN_payload.zip");
            string iconPath = Path.Combine(root, "app_icon.ico");

            foreach (string path in new[] { uiScript, installScript, payloadZip, iconPath })
            {
                RemoveInternetZone(path);
            }

            if (!File.Exists(uiScript) || !File.Exists(installScript) || !File.Exists(payloadZip))
            {
                throw new FileNotFoundException("The Green VPN installer payload is incomplete.");
            }

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = "powershell.exe";
            startInfo.Arguments =
                "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File " +
                Quote(uiScript);
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;

            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                {
                    throw new InvalidOperationException("The Green VPN installer process did not start.");
                }

                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception exception)
        {
            WriteFailureLog(exception);
            MessageBox.Show(
                "Green VPN could not start the installation. Please download the installer again.",
                "Green VPN Installer",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }
}
