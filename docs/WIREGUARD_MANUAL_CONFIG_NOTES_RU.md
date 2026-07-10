# WireGuard Manual Config Notes

## London/RUVDS manual configs

- Visible Windows desktop for this machine is `C:\Users\gekto\OneDrive\Desktop`.
- Manual London WireGuard configs for people/devices are kept in:
  `C:\Users\gekto\OneDrive\Desktop\GreenVPN London WireGuard`.
- If these configs need a fix, edit the existing files in that folder in place. Do not create a second replacement folder unless the owner explicitly asks for it.
- For client `[Peer] PublicKey`, use the active server public key from:
  `wg show wg0 public-key`
  or `/etc/wireguard/server_public.key`.
- Do not use `/etc/wireguard/wg0_server_public.key` for London/RUVDS manual configs. It was stale and caused clients to show "connected" while receiving 0 bytes.
- Never write WireGuard private keys, preshared keys, API tokens, SMTP secrets, SMS secrets, YooKassa secrets, or other credentials into repo docs.
