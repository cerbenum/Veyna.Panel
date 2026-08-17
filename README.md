<div align="center">

<img src="logo.png" alt="VEYNA" width="110">

# VEYNA Panel

**One command. Your server. Your users.**

<img src="https://img.shields.io/badge/Ubuntu-22.04+-E95420?style=for-the-badge&logo=ubuntu&logoColor=white&labelColor=1a1a1a" alt="Ubuntu">
&nbsp;
<img src="https://img.shields.io/badge/Debian-12+-A81D33?style=for-the-badge&logo=debian&logoColor=white&labelColor=1a1a1a" alt="Debian">
&nbsp;
<img src="https://img.shields.io/badge/x86__64-2a2a2a?style=for-the-badge&logo=linux&logoColor=white&labelColor=1a1a1a" alt="x86_64">

</div>

---

<div align="center">

### ⌘ &nbsp;Install &nbsp;·&nbsp; نصب

</div>

```bash
curl -fsSL https://raw.githubusercontent.com/cerbenum/Veyna.Panel/main/installer/install.sh | sudo bash
```

<div align="center">
<sub>Everything else — database, web server, certificates, the VPN node — is set up for you.</sub><br>
<sub dir="rtl">بقیه‌اش — دیتابیس، وب‌سرور، گواهی، و خود نود — خودکار نصب می‌شه.</sub>
</div>

---

<table>
<tr>
<td width="50%" valign="top">

### English

**After install**

The installer prints your panel address and admin path. Open it and sign in.

```bash
sudo veyna-panelctl info      # your panel URL
sudo veyna-panelctl status    # is it running
sudo veyna-panelctl health    # is it healthy
```

**Non-interactive**

```bash
curl -fsSL https://raw.githubusercontent.com/cerbenum/Veyna.Panel/main/installer/install.sh -o install.sh
sudo bash install.sh -y \
  --domain panel.example.com \
  --admin-user admin \
  --admin-pass 'ChangeThis123!'
```

`sudo bash install.sh --help` lists every option.

**Updating**

Re-run the installer. Your admin path, keys and database password stay exactly as they were.

</td>
<td width="50%" valign="top" dir="rtl">

### فارسی

**بعد از نصب**

نصاب آدرس پنل و مسیر ادمین رو چاپ می‌کنه. بازش کن و وارد شو.

```bash
sudo veyna-panelctl info      # آدرس پنل
sudo veyna-panelctl status    # وضعیت اجرا
sudo veyna-panelctl health    # سلامت سرویس
```

**نصب بدون تعامل**

```bash
curl -fsSL https://raw.githubusercontent.com/cerbenum/Veyna.Panel/main/installer/install.sh -o install.sh
sudo bash install.sh -y \
  --domain panel.example.com \
  --admin-user admin \
  --admin-pass 'ChangeThis123!'
```

`sudo bash install.sh --help` همهٔ گزینه‌ها رو نشون می‌ده.

**به‌روزرسانی**

نصاب رو دوباره اجرا کن. مسیر ادمین، کلیدها و رمز دیتابیس دست‌نخورده می‌مونن.

</td>
</tr>
</table>

---

<div align="center">

<sub>Client app &nbsp;·&nbsp; برنامهٔ کلاینت</sub>

<a href="https://github.com/cerbenum/Veyna.App">
<img src="https://img.shields.io/badge/VEYNA-App-5B5BD6?style=for-the-badge&logoColor=white&labelColor=1a1a1a" alt="Veyna App">
</a>

<br><br>

<sub>Proprietary — see [LICENSE](LICENSE). This repository ships the installer only; the source is closed.</sub>

<br>

**Cerbenum**

</div>
