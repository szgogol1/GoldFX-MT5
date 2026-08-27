# 推送到 GitHub（用户 szgogol1）

目标仓库建议名：`GoldFX-MT5`  
完整地址：`https://github.com/szgogol1/GoldFX-MT5`

> 云端 Agent 没有你的 GitHub 凭证，**必须在你本机 Cursor 终端执行**下面步骤。

## 第 0 步：完成 GitHub Connect

1. Cursor → Settings → Integrations → **Connect GitHub**  
2. 或打开 https://cursor.com/settings → Integrations → GitHub → Connect  
3. 用账号 **szgogol1** 授权

## 第 1 步：在 GitHub 新建空仓库

1. 打开：https://github.com/new  
2. Repository name：`GoldFX-MT5`  
3. Public 或 Private 均可  
4. **不要**勾选 Add README / .gitignore / license（保持空仓库）  
5. 点 **Create repository**

## 第 2 步：在本机 Cursor 终端推送

若你已经能打开本工程文件夹，在终端执行：

```powershell
# 进入工程根目录（按你实际路径改）
cd D:\GoldFX-MT5_repo
# 或你 clone / 打开的 GoldFX 项目根目录

git remote remove github 2>$null
git remote add github https://github.com/szgogol1/GoldFX-MT5.git
git push -u github main
```

若提示登录：按弹窗用浏览器登录 **szgogol1**，或改用：

```powershell
# 需已安装 GitHub CLI 并登录
gh auth login
gh repo create szgogol1/GoldFX-MT5 --private --source=. --remote=github --push
```

## 第 3 步：本机下载到 D 盘（以后都用这个）

```powershell
cd D:\
git clone https://github.com/szgogol1/GoldFX-MT5.git GoldFX-MT5
cd D:\GoldFX-MT5
.\install_to_MT5.bat
```

仓库结构（根目录即源码，无重复子目录）：

- `Experts/`、`Include/`、`Presets/`
- 安装脚本：`install_to_MT5.bat` / `install_to_MT5.ps1`

## 一键脚本（可选）

工程内已提供：`scripts/push_to_github.ps1`  
在 Cursor 终端：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\push_to_github.ps1
```

## 推送成功后

打开确认：https://github.com/szgogol1/GoldFX-MT5  

然后告诉我「已推送」，我可以继续帮你写 MT5 安装核对清单。
