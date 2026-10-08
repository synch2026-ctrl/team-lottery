# 小组抽签

这是一个静态网页，使用 Supabase 保存共享房间和成员名单，使用 GitHub Pages 发布。创建房间后，发起人分享邀请链接；成员通过链接自行加入，发起人抽签后所有人都会看到相同结果。人数上限为 2–20 人，房间 24 小时后失效。

## 1. 配置 Supabase

1. 使用 GitHub 账号登录 [Supabase](https://supabase.com/dashboard)，创建一个项目。
2. 打开项目的 **SQL Editor**，运行本目录的 `supabase-schema.sql` 全部内容。
3. 在项目的 **Connect** 或 **API Settings** 页面找到 Project URL 和 `anon` / publishable key。
4. 将这两项填入 `config.js`。这两项是前端公开配置；不要把 `service_role` 或 secret key 放进网页。

## 2. 发布到 GitHub Pages

1. 在 GitHub 新建一个 **Public** 仓库，将 `index.html`、`style.css`、`config.js`、`README.md` 上传到仓库根目录。
2. 打开仓库的 **Settings → Pages**，选择从 `main` 分支的根目录部署并保存。
3. 等待 GitHub Pages 部署完成。仓库 Pages 页面会显示可分享的网址。

## 使用方式

发起人打开网站、设置房间人数上限并创建房间，然后复制邀请链接发到群里。每位成员打开链接后填写姓名加入；名单会自动刷新。发起人的主持人凭证仅保存在创建房间的浏览器会话中，可以在至少两位成员加入后抽签。分享出去的邀请链接不包含主持人凭证；更换浏览器或清除会话后，发起人需重新创建房间。

房间只开放所需的数据库函数调用；客户端不能直接读写数据库表。公开网站所需的 Supabase URL 和 publishable/anon key 可以被访问者看到，因此不要在网页中放置任何服务端密钥。
