# 🛡️ BestTunnel-X v2.0

**تونل GRE حرفه‌ای بین سرور ایران و خارج + فوروارد پورت چندپروتکلی**

بازنویسی کامل و امن‌سازی‌شدهٔ [alirezalaleh2005/BestTunnel](https://github.com/alirezalaleh2005/BestTunnel) — بدون باینری خارجی، بدون `curl | bash` ناشناس، بدون license removed.

---

## 📋 فهرست

- [چرا BestTunnel-X](#-چرا-besttunnel-x)
- [ویژگی‌ها](#-ویژگیها)
- [معماری](#-معماری)
- [پیش‌نیازها](#-پیشنیازها)
- [نصب](#-نصب)
- [راهنمای کامل دستورات](#-راهنمای-کامل-دستورات)
- [سناریوهای کاربردی](#-سناریوهای-کاربردی)
- [عیب‌یابی](#-عیب‌یابی)
- [امنیت](#-امنیت)
- [تفاوت با نسخه اصلی](#-تفاوت-با-نسخه-اصلی)
- [حذف کامل](#-حذف-کامل)
- [ساختار فایل‌ها](#-ساختار-فایل‌ها)
- [لایسنس](#-لایسنس)

---

## 🤔 چرا BestTunnel-X؟

نسخه اصلی GitHub این مشکلات را داشت:

| ❌ مشکل | 💥 پیامد |
|---|---|
| دانلود `Paqet-X` از `http://*.iliyadev.ir:8080` | باینری ناشناس، HTTP بدون checksum، قابل جایگزینی با malware |
| کامنت "(License Removed Version)" | کپی غیرقانونی از ابزار شخص دیگر |
| `curl \| bash` روی root | اجرای کد ناشناس با دسترسی کامل |
| `valid_mtu` تعریف نشده | MTU اصلاً اعتبارسنجی نمی‌شد |
| Syntax error در `uninstall_clean` | حذف تونل fail می‌شد |
| `mkdir -p` روی مسیر فایل لاگ | خرابکاری فایل‌سیستم |
| Regenerate IP تصادفی | تونل هر بار IP عوض می‌کرد — غیرقابل پیش‌بینی |
| فقط منوی interactive | قابل اسکریپت نبود |

**BestTunnel-X همهٔ این‌ها را فیکس می‌کند** و یک ابزار production-ready می‌دهد که خودت می‌توانی هر خطش را بخوانی.

---

## ✨ ویژگی‌ها

### هسته
- 🚇 تونل **GRE** با آدرس‌دهی `/30` نقطه‌به‌نقطه
- 🔑 **Keyed GRE** (کلید = `id × 100`) برای جداسازی تونل‌های موازی
- 📏 **MTU** قابل تنظیم 576 تا 9000 — live بدون ری‌استارت
- 🎯 تونل‌های موازی با ID مجزا (`grex1`، `grex2`، … تا 255)

### فورواردینگ
- 🌐 **TCP + UDP + both** در یک دستور
- 📦 **Port ranges**: `8000-8010` یک خطی
- ♻️ **auto-restart** هر forwarder با `Restart=always`
- 🗂 فایل `*.ports` جدا برای هر تونل — audit آسان

### پایداری
- 🩺 **Watchdog** با cron هر دقیقه — ping به peer + restart خودکار
- 💾 **Backup خودکار** همه unit‌ها در `/var/lib/besttunnel-x/backup/`
- 📜 **لاگ مرکزی** `/var/log/besttunnel-x.log` با timestamp

### اینترنت‌شaring
- 🌍 **NAT (masquerade)** روی اینترفیس تونل
- 🔧 **MSS clamping** خودکار — جلوی fragmentation را می‌گیرد
- ⚙️ فعال‌سازی `ip_forward` خودکار

### مدیریت
- 🖥 **CLI کامل** — قابل استفاده در اسکریپت/آنسیبل/cron
- 🎨 خروجی رنگی با Unicode icons
- 📊 `status` — آمار لینک، RTT، وضعیت هر forwarder
- 🧹 `purge` — حذف مطلق همه‌چیز (تونل‌ها، واحدها، watchdog، NAT، لاگ)

---

## 🏗 معماری

```
┌──────────────────┐                    ┌──────────────────┐
│   IRAN  Server   │                    │  KHAREJ  Server  │
│                  │                    │                  │
│  Public: 5.6.7.8 │                    │  Public: 1.2.3.4 │
│                  │   GRE tunnel over  │                  │
│  grex1           │◄═public internet═► │  grex1           │
│  10.240.1.1/30   │    key=100         │  10.240.1.2/30   │
│                  │                    │                  │
│  socat :22 ──────┼─► 10.240.1.2:22 ─► │   sshd :22       │
│  socat :80 ──────┼─► 10.240.1.2:80 ─► │   nginx :80      │
│  socat :443 ─────┼─► 10.240.1.2:443 ► │   nginx :443     │
└──────────────────┘                    └──────────────────┘
```

کلاینت به IP **ایران** وصل می‌شود؛ socat ترافیک را داخل تونل به خارج می‌فرستد؛ سرویس واقعی روی خارج جواب می‌دهد. IP خارجی هرگز در معرض کاربر نهایی قرار نمی‌گیرد.

---

## 📦 پیش‌نیازها

| نیاز | دستور نصب |
|---|---|
| Debian / Ubuntu (systemd) | — |
| `iproute2`, `socat` | نصب خودکار با `ensure_deps` |
| `nftables` | برای `nat` (اختیاری) |
| `iputils-ping` | برای `watchdog` و `status` |
| کرنل با `ip_gre` | پیش‌فرض در همه کرنل‌های مدرن |
| **root** | همه عملیات نیاز به root دارند |

---

## 🚀 نصب

### روش ۱ — نصب تک‌دستوری ⭐ (سریع‌ترین)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh)
```

یا:

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh | sudo bash
```

اسکریپت `install.sh` خودش:
- `besttunnel-x.sh` را از GitHub دانلود می‌کند
- sanity-check می‌کند (bash syntax + مارکر + تابع اصلی)
- به `/usr/local/bin/btx` نصب می‌کند
- `LICENSE` و `README` را در `/usr/local/share/` می‌گذارد
- وابستگی‌های لازم (`iproute2`، `socat`، `iputils-ping`) را نصب می‌کند

**⚠️ هشدار:** همیشه قبل از `curl | bash` اسکریپت را باز کن و بخوان — این یک عادت امنیتی است نه یک کلیشه.

### روش ۲ — نصب محلی از ZIP

اگر فایل ZIP را دانلود کردی:

```bash
unzip besttunnel-x.zip
cd besttunnel-x
sudo bash install.sh
```

`install.sh` هوشمند است — اگر `besttunnel-x.sh` کنارش باشد، از همان استفاده می‌کند و دانلود نمی‌کند.

### روش ۳ — نصب دستی

```bash
sudo install -m 755 besttunnel-x.sh /usr/local/bin/btx
```

### بررسی

```bash
btx --version   # → besttunnel-x 2.0
btx --help
```

---

## 📖 راهنمای کامل دستورات

### 1️⃣ `create` — ساخت تونل

```bash
btx create <role> <id> <local_pub_ip> <remote_pub_ip> <mtu> [port | range ...]
```

| آرگومان | توضیح |
|---|---|
| `role` | `iran` (با فوروارد) یا `kharej` (فقط endpoint) |
| `id` | عدد ۱ تا ۲۵۵ — نام اینترفیس `grex<id>` می‌شود |
| `local_pub_ip` | IP عمومی همین سرور |
| `remote_pub_ip` | IP عمومی سرور روبرو |
| `mtu` | 576–9000، معمولاً `1400` یا `1476` |
| `ports` | اختیاری — فقط برای `iran`؛ تک‌پورت `80` یا رنج `8000-8010` |

**مثال:**

```bash
# روی سرور ایران (IP عمومی: 5.6.7.8)، سرور خارج (1.2.3.4)
btx create iran 1 5.6.7.8 1.2.3.4 1400 22 80 443 9000-9010
```

**نتیجه:**
- اینترفیس `grex1` با `10.240.1.1/30` ساخته می‌شود
- ۴ فوروارد TCP: `22`, `80`, `443`, و `9000` تا `9010` (۱۱ پورت)
- سرویس‌ها: `grex1.service` + `fx-grex1-tcp{PORT}.service` × ۱۴

---

### 2️⃣ `peer` — ساخت طرف خارج (میان‌بر)

```bash
btx peer <id> <local_pub> <remote_pub> <mtu>
# معادل: btx create kharej <id> <local_pub> <remote_pub> <mtu>
```

**مثال:**

```bash
# روی سرور خارج
btx peer 1 1.2.3.4 5.6.7.8 1400
```

---

### 3️⃣ `addport` / `delport` — مدیریت پورت

```bash
btx addport <id> <tcp|udp|both> <port|range> [more...]
btx delport <id> <tcp|udp> <port>
```

**مثال‌ها:**

```bash
btx addport 1 tcp 8080 8081-8090      # ۱۰ پورت TCP
btx addport 1 udp 53 51820            # DNS + WireGuard
btx addport 1 both 1194               # OpenVPN TCP+UDP
btx delport 1 tcp 8080
```

---

### 4️⃣ `mtu` — تغییر MTU زنده

```bash
btx mtu <id> <mtu>
btx mtu 1 1476      # apply زنده، بدون ری‌استارت
```

---

### 5️⃣ `nat` — ماسکرید + MSS clamp

```bash
btx nat <id> on     # فعال‌سازی
btx nat <id> off    # حذف
```

این کار:
- جدول `inet btx` در nftables می‌سازد
- `masquerade` روی ترافیک خروجی از `grex<id>` اعمال می‌کند
- MSS را روی `1360` clamp می‌کند (جلوگیری از fragmentation داخل GRE)
- `net.ipv4.ip_forward=1` را فعال می‌کند

**کی لازم است؟** وقتی می‌خواهی سرور ایران را مثل یک VPN gateway به خارج وصل کنی — کلاینت‌ها traffic را به سرور ایران می‌دهند و از طریق تونل به اینترنت خارج می‌روند.

---

### 6️⃣ `watchdog` — بررسی سلامت خودکار

```bash
btx watchdog on     # نصب cron هر دقیقه
btx watchdog off    # حذف
```

**کاری که می‌کند:**
- هر دقیقه همه تونل‌های فعال را چک می‌کند
- اگر `systemd unit` غیرفعال شد → restart
- اگر `ping` به `TUN_REMOTE` (۳ ثانیه timeout) جواب نداد → restart
- همه وقایع را در `/var/log/besttunnel-x.log` می‌نویسد

---

### 7️⃣ `list` — داشبورد همه تونل‌ها

```bash
btx list
```

**خروجی نمونه:**

```
grex1   role=iran    5.6.7.8 <-> 1.2.3.4    tun=10.240.1.1/30   mtu=1400  rtt=87.4ms
    tcp :22     active
    tcp :80     active
    tcp :443    active
    tcp :9000   active
    ...

grex2   role=iran    5.6.7.8 <-> 9.8.7.6    tun=10.240.2.1/30   mtu=1476  rtt=—
```

---

### 8️⃣ `status` — جزئیات یک تونل

```bash
btx status 1
```

**خروجی شامل:**
- `ip -d link show grex1` — پارامترهای تونل (key, ttl, remote, local)
- `ip -s link` — شمارنده‌های RX/TX packet/byte
- `ping -c3` به peer — RTT و packet loss
- لیست systemd واحدهای forwarder با وضعیت

---

### 9️⃣ `remove` / `purge` — حذف

```bash
btx remove 1    # فقط grex1 — service‌ها، config، backup همه پاک می‌شوند
btx purge       # همه تونل‌ها + watchdog + NAT + لاگ — ریست کامل
```

---

### 🔟 `logs` — دیدن لاگ

```bash
btx logs        # آخرین ۵۰ خط /var/log/besttunnel-x.log
```

---

## 🎯 سناریوهای کاربردی

### سناریو A — سرویس وب پشت سرور خارج

هدف: کاربر به `5.6.7.8:443` (ایران) وصل شود ولی سایت روی `1.2.3.4` (خارج) میزبانی شود.

```bash
# روی خارج:
btx peer 1 1.2.3.4 5.6.7.8 1400

# روی ایران:
btx create iran 1 5.6.7.8 1.2.3.4 1400 80 443
btx watchdog on
```

حالا `curl http://5.6.7.8/` مستقیم از سرور خارج سرو می‌شود.

---

### سناریو B — SSH پنهان

هدف: `ssh user@5.6.7.8` به SSH روی خارج برود.

```bash
btx create iran 1 5.6.7.8 1.2.3.4 1400 22
```

روی خارج، `sshd` روی 22 گوش می‌دهد — کاربر ایران IP خارج را نمی‌بیند.

---

### سناریو C — WireGuard پشت GRE

هدف: WireGuard که UDP است و مستقیم فیلتر می‌شود، داخل GRE قایق شود.

```bash
# روی خارج، WireGuard روی 51820 گوش می‌دهد
btx peer 1 1.2.3.4 5.6.7.8 1400

# روی ایران
btx create iran 1 5.6.7.8 1.2.3.4 1400
btx addport 1 udp 51820
```

WireGuard client به `5.6.7.8:51820` وصل می‌شود و ترافیک UDP داخل GRE می‌رود.

---

### سناریو D — اینترنت share (VPN-style)

هدف: کلاینت‌ها روی سرور ایران route شوند و از IP خارج به اینترنت بروند.

```bash
# روی خارج:
btx peer 1 1.2.3.4 5.6.7.8 1400
btx nat 1 on        # masquerade روی grex1

# روی ایران:
btx create iran 1 5.6.7.8 1.2.3.4 1400
btx nat 1 on
# سپس route کلاینت‌ها را به 10.240.1.1 بده
```

---

### سناریو E — چند تونل موازی (HA / load distribution)

```bash
btx create iran 1 5.6.7.8 1.2.3.4 1400 80
btx create iran 2 5.6.7.8 9.8.7.6 1400 80   # سرور خارج دوم
btx create iran 3 5.6.7.8 5.5.5.5 1400 80   # سرور خارج سوم

btx list    # هر ۳ تا را با RTT می‌بینی
```

---

## 🔍 عیب‌یابی

### تونل up است ولی ping peer کار نمی‌کند

```bash
# چک سمت روبرو — باید `peer` یا `create kharej` اجرا شده باشد
ssh root@1.2.3.4 'btx list'

# چک GRE encapsulation می‌رسد یا نه
tcpdump -i eth0 proto gre   # باید packet ببینی

# چک firewall — GRE protocol number 47 است نه port
nft list ruleset | grep -i gre
iptables -L -n | grep 47
```

**شایع‌ترین علت:** فایروال سرور (یا provider شبکه) پروتکل GRE (IP proto 47) را drop می‌کند. بعضی datacenterها GRE را مسدود می‌کنند — باید تیکت بزنی.

### forwarder کار نمی‌کند

```bash
systemctl status fx-grex1-tcp80.service
journalctl -u fx-grex1-tcp80.service -n 50

# تست دستی socat
socat TCP-LISTEN:8080,reuseaddr,fork TCP:10.240.1.2:80
curl http://localhost:8080/
```

### packet loss بالا

```bash
# MTU را پایین بیا
btx mtu 1 1380
btx mtu 1 1280

# یا MSS clamp را روشن کن
btx nat 1 on
```

### تونل بعد از reboot بالا نمی‌آید

```bash
systemctl is-enabled grex1.service   # باید enabled باشد
systemctl enable grex1.service
```

### لاگ‌ها را کجا ببینم

```bash
btx logs                                # لاگ خود ابزار
journalctl -u grex1.service -f          # لاگ تونل
journalctl -u "fx-grex1-*" -f           # لاگ همه forwarderها
tail -f /var/log/syslog | grep grex     # لاگ سیستم
```

---

## 🔐 امنیت

### چه چیزی این نسخه امن‌تر است

| موضوع | پیاده‌سازی |
|---|---|
| **بدون binary خارجی** | فقط `ip`, `socat`, `nft` — همه از repo رسمی توزیع |
| **بدون curl\|bash** | نصب با copy فایل یا install محلی |
| **Permissions** | `/etc/besttunnel-x/*.conf` → `chmod 600` |
| **Validation** | همه ورودی‌ها (IP, port, MTU, id) قبل از اجرا چک می‌شوند |
| **Audit trail** | همه عملیات در `/var/log/besttunnel-x.log` |
| **Idempotent** | اجرای دوباره دستور خراب نمی‌کند |
| **No telemetry** | هیچ دیتایی به جایی ارسال نمی‌شود |

### ⚠️ چیزهایی که باید خودت اضافه کنی

**GRE ذاتاً رمزنگاری ندارد.** ترافیک داخل تونل به‌صورت plaintext روی اینترنت می‌رود. اگر محرمانگی می‌خواهی:

1. **روی GRE یک VPN بگذار** (WireGuard/OpenVPN/IPsec) — الگوی رایج
2. **یا خود GRE را با IPsec ترکیب کن** — `gre + ipsec transport mode`
3. **یا از یک تونل encrypted مثل WireGuard استفاده کن** — ساده‌تر

نمونه ترکیب با WireGuard:

```bash
# روی هر دو سرور
apt install wireguard
# کلید بساز، peer اضافه کن، allowed_ips = 10.240.1.0/30
# حالا ترافیک GRE داخل WireGuard رمز می‌شود
```

### فایروال

دستورات زیر را خودت بسته به نیاز اضافه کن:

```bash
# اجازه GRE از IP خاص
nft add rule inet filter input ip protocol gre ip saddr 1.2.3.4 accept
nft add rule inet filter input ip protocol gre drop

# یا با iptables
iptables -A INPUT -p gre -s 1.2.3.4 -j ACCEPT
iptables -A INPUT -p gre -j DROP
```

---

## 🔄 تفاوت با نسخه اصلی

| قابلیت | GitHub BestTunnel | BestTunnel-X |
|---|---|---|
| باینری خارجی | `Paqet-X` از HTTP | ❌ هیچی |
| لایسنس | "Removed" | AGPL-3.0 |
| UDP forward | ❌ | ✅ |
| Port ranges | ❌ | ✅ `8000-8010` |
| Watchdog | ❌ | ✅ cron |
| NAT + MSS | ❌ | ✅ |
| Dashboard | ❌ | ✅ `status` |
| Backup | ناقص | ✅ خودکار |
| CLI | فقط منو | ✅ کامل |
| Multi-tunnel | بله، ولی با bug | ✅ تا 255 |
| Validation | ناقص | ✅ کامل |
| لاگ | پراکنده | ✅ متمرکز |
| Bug‌های syntax | چندتا | فیکس |
| Codename | `greN` | `grexN` |

---

## 🗑 حذف کامل

```bash
btx purge                    # حذف همه تونل‌ها + watchdog + NAT
sudo bash uninstall.sh       # حذف /usr/local/bin/btx + همه فایل‌ها
```

فایل‌هایی که پاک می‌شوند:
- `/usr/local/bin/btx`
- `/etc/besttunnel-x/` — کانفیگ‌ها و لیست پورت‌ها
- `/var/lib/besttunnel-x/` — backup ها و state
- `/var/log/besttunnel-x.log`
- `/usr/local/libexec/besttunnel-x-watchdog`
- `/etc/cron.d/besttunnel-x-watchdog`
- همه `grex*.service` و `fx-grex*-*.service` در systemd
- اینترفیس‌های `grex*` فعال

---

## 📁 ساختار فایل‌ها

### داخل ZIP

```
besttunnel-x/
├── besttunnel-x.sh      ← اسکریپت اصلی (~14 KB، ~370 خط)
├── install.sh           ← نصب‌کننده محلی
├── uninstall.sh         ← حذف کامل
└── README.md            ← همین فایل
```

### بعد از نصب روی سیستم

```
/usr/local/bin/btx                                    ← binary اصلی
/etc/besttunnel-x/
    1.conf              ← config تونل ۱ (mode 600)
    1.ports             ← لیست forwarderها (mode 600)
    2.conf, 2.ports     ← تونل دوم
    ...
/var/lib/besttunnel-x/
    backup/1/grex1.service, fx-grex1-tcp22.service, ...
    state/              ← state runtime
/etc/systemd/system/
    grex1.service
    fx-grex1-tcp22.service
    fx-grex1-tcp80.service
    ...
/usr/local/libexec/besttunnel-x-watchdog              ← اسکریپت watchdog
/etc/cron.d/besttunnel-x-watchdog                     ← کرون هر دقیقه
/var/log/besttunnel-x.log                             ← لاگ مرکزی
```

### فرمت `*.conf`

```bash
# besttunnel-x tunnel 1
ID=1
ROLE=iran               # iran | kharej
LOCAL_IP=5.6.7.8
REMOTE_IP=1.2.3.4
TUN_LOCAL=10.240.1.1
TUN_REMOTE=10.240.1.2
MTU=1400
KEY=100                 # = ID * 100
CREATED="2026-10-19 14:32:11"
```

### فرمت `*.ports`

```
tcp 22
tcp 80
tcp 443
udp 51820
```

---

## 🧪 تست سریع

بعد از setup:

```bash
# از ایران به خارج — باید جواب بده
ping -c3 10.240.1.2

# باید جواب بده
curl http://10.240.1.2/

# باید از سرور خارج سرو شود (نه ایران)
curl http://5.6.7.8/

# چک روی خارج
tcpdump -i grex1     # باید ترافیک TCP:80 ببینی
```

---

## 🤝 مشارکت

این نسخه کاملاً باز و قابل audit است. اگر باگی پیدا کردی یا قابلیتی می‌خواهی:

1. کد را بخوان — فقط ~370 خط است
2. تغییر بده
3. تست کن: `bash -n besttunnel-x.sh` باید بدون خطا باشد
4. PR بفرست یا برای خودت نگه دار

---

## ⚠️ سلب مسئولیت

- این ابزار برای **استفاده قانونی** (VPN شخصی، شبکه سازمانی، آزمایش) ساخته شده.
- GRE رمزنگاری ندارد — برای محرمانگی، آن را با یک لایه encryption ترکیب کن.
- برخی providerها GRE (IP proto 47) را block می‌کنند — قبل از production تست کن.
- مسئولیت استفاده بر عهده کاربر است.

---

## 📜 لایسنس

```
BestTunnel-X — hardened GRE tunnel manager
Copyright (C) 2026

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License v3.0.
```

---

**ساخته شده با ❤️ — بدون `curl | bash`، بدون باینری ناشناس، بدون license removed.**
