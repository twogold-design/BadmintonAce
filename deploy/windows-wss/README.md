# Windows 云服务器：无需域名的 WSS 入口

**带流量保护的完整包**：若使用 `BadmintonAce-Protected-Server.zip`，请先读 [PROTECTED-SERVER.md](PROTECTED-SERVER.md)，只启动 `start-protected.cmd`，由它同时管理后台与 WSS。下文单独启动两项服务的步骤仅适用于旧版 WSS 附加包，不带流量保护。

适用：Windows Server 2022 x64、公网 IP 121.40.81.89，现有 BadmintonAce-Server.exe 在 8766 端口运行。
本包是加密入口附加包，不含游戏资源、玩家数据库或后台 EXE。

## 部署

1. 把 BadmintonAce-WSS-Windows.zip 上传到云服务器，完整解压到一个长期保留、可写的独立文件夹。
2. 阿里云实例安全组入方向：允许 TCP 80 和 TCP 443，来源 0.0.0.0/0。不要改动远程桌面管理规则。无需开放 UDP。
3. 在云服务器上右键 allow-wss.cmd → 以管理员身份运行。该脚本只为此目录中的 caddy.exe 放行 Windows 防火墙 TCP 80/443，不关闭防火墙，不修改其他规则。
4. 保持原有 BadmintonAce-Server.exe 运行；在云服务器浏览器访问 http://127.0.0.1:8766/health，确认 ok:true、version:5。
5. 双击 start-wss.cmd。不要只双击 caddy.exe。首次启动会通过 Let's Encrypt 申请公网 IP 证书；配置使用正式证书服务，其订户条款见 https://letsencrypt.org/repository/ 。保持窗口打开以便自动续期。
6. 在自己电脑浏览器访问 https://121.40.81.89/health，必须没有证书警告，并返回 ok:true、version:5、transport:websocket-relay。若有证书警告，不要绕过；查看 Caddy 窗口报错。
7. 验证成功后，把玩家包 config.js 的赋值改为：

```js
window.ACE_SERVER = 'wss://121.40.81.89/ws';
```

在工程中同时修改 tools/web-config.js 与 build/web/config.js，再打包上传比赛平台。WSS 使用默认 443，不要写成 :8766。现有客户端配置不会由本附加包自动修改。

8. WSS 联机验证成功后，在阿里云安全组及 Windows 防火墙删除或禁用此前的 8766 公网允许规则。保留后台 EXE 运行，Caddy 通过本机 127.0.0.1:8766 转发。不要删除 80/443 或自己的远程管理规则。

云端只发布 /health 和 /ws；/gm 和游戏资源路径均不会转发。
现有后台直接双击使用默认 TRUST_PROXY=0，避免直接端口仍开放时误信代理头；此模式下登录限流按代理共用额度（每分钟 120 次）。后续扩大人数时，应先限制后台仅本机可达，再启用可信代理配置。

## 每次开机与续期

- 这份简单启动包没有安装开机自启服务。云服务器重启后，需要重新启动后台 EXE 和 start-wss.cmd。
- 关闭远程桌面连接通常会保留程序；注销 Windows 用户、关闭窗口或关机会停止程序。不要注销运行服务的用户。
- Let's Encrypt 的 IP 证书有效期约 6 天，Caddy 运行期间自动续期。80/443 需要持续可达。wss-state 中保存证书私钥和账号信息，不要删除、公开或提交 Git。
- 长期关机后，先让 Caddy 完成续期，再让玩家登录。
- 节省停机模式会回收普通公网 IP。IP 变化时需更新 Caddyfile 的站点地址、default_sni 和所有玩家包中的地址，重启 Caddy 申请新 IP 证书；旧 IP 证书不能用于新地址。

## 排查

- 本机 HTTP /health 不通：先检查后台 EXE，不是证书问题。
- 公网 HTTPS 超时：检查两层防火墙、安全组、端口是否被 IIS/其他程序占用，以及云侧访问策略。
- Caddy 提示 address already in use：80/443 被占用，先确认占用服务用途，不要盲目停服务。
- 返回 502：Caddy 已接到请求，但 127.0.0.1:8766 后台未正常运行。
- 日志提示证书签发成功，但浏览器 TLS 握手失败：确认全局配置包含 default_sni 121.40.81.89（与当前公网 IP 一致）。直接访问 IP 的浏览器通常不发送 SNI，而云主机网卡是私网地址，需要此默认值选择正确的公网 IP 证书。
- 提示申请证书失败：保留完整错误，检查公网 IP 是否仍属于本实例、80/443 的外部可达性和云服务器访问证书服务的网络。不要切换成自签证书让玩家忽略警告。
- /health 正常但平台试玩仍失败：检查上传包的 config.js，以及平台是否允许连接 wss://121.40.81.89；平台 CSP 等策略仍可能限制外部服务。

## 官方资料

- Caddy 2.11.7：https://github.com/caddyserver/caddy/releases/tag/v2.11.7
- TLS / ACME profile：https://caddyserver.com/docs/caddyfile/directives/tls
- IP 证书：https://letsencrypt.org/2026/01/15/6day-and-ip-general-availability

本地配置检查不等同于云端签发证书成功，必须完成第 6 步和比赛页面实际联机测试。
