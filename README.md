# shelfseer

> Talk to the library you already own — your notes, your documents, the books you bound yourself — entirely on your Mac, 100% offline.
>
> 與你早已擁有的書庫對話 —— 你的筆記、你的文件、你親手裝幀的書 —— 全程在你的 Mac 上，完全離線。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-black?logo=apple)](https://www.apple.com/macos/)
[![Status: early](https://img.shields.io/badge/status-early%20development-orange)](#status)

**No API keys · No subscriptions · No internet · Your library never leaves your machine.**

> ⚠️ **Status.** shelfseer is at the concept/scaffold stage — not yet usable. This README describes the intended product. Watch the repo for the first working build.

[**English**](#english) ・ [**繁體中文**](#繁體中文)

---

## English

### What shelfseer is

shelfseer points a small, **on-device** language model at a folder of documents **you own** — and lets you ask it questions, find passages, and get answers grounded in *your own* texts. Nothing is uploaded; there is no pipe to the outside world.

It is the companion to **[reepub](https://github.com/CVERInc/reepub)**, which turns the paper you own into a personal library of clean, reflowable EPUBs. Together they tell one story:

> **reepub binds your paper into a library you own. shelfseer lets you talk to it. First you own the books — then you own the librarian.**

### Why on-device

The intelligence here lives mostly in **retrieval** — finding the right passages from your own library — so a small local model is enough. That means the whole thing can run on your Mac, which buys you what no cloud service can sell:

- **Ownership, not rental.** A capability that lives on your shelf — no one can reprice it, gate it, or switch it off.
- **Privacy that's structural, not a promise.** Your most private text (journals, letters, manuscripts) never leaves the machine. There is no pipe.
- **Offline & permanent.** Works with no network, no account, and keeps working regardless of any vendor.

### Intended use

shelfseer is for querying documents **you own or have the right to read** — your own writing, notes and correspondence, public-domain works, or books you physically own. Everything is processed locally; nothing is ever uploaded. Please respect copyright and the rights of authors and publishers.

### Status

Early development. The name and concept are locked; the implementation has not started. See the repo for progress.

### License

MIT — see [LICENSE](LICENSE). © 2026 CVER Inc.

---

## 繁體中文

### shelfseer 是什麼

shelfseer 把一個小型、**在裝置上執行**的語言模型，指向一個**你擁有的**文件資料夾 —— 讓你對它提問、找出段落，並得到**根據你自己文本**而來的回答。一切都不會上傳；沒有任何一條通向外界的管線。

它是 **[reepub](https://github.com/CVERInc/reepub)** 的同門夥伴 —— reepub 把你擁有的紙，裝幀成乾淨、可重排的私人 EPUB 書庫。兩者合起來說的是同一個故事：

> **reepub 把你的紙裝幀成你擁有的書庫，shelfseer 讓你與它對話。先擁有書 —— 再擁有圖書館員。**

### 為什麼要在裝置上跑

這裡的「聰明」主要在**檢索** —— 從你自己的書庫裡找出對的段落 —— 所以一個小型本地模型就夠了。這代表整套東西能在你的 Mac 上執行，換來雲端服務賣不了你的東西：

- **擁有，而非租用。** 一份住在你書架上的能力 —— 沒人能漲它的價、把它上鎖、或關掉它。
- **結構性的隱私，而非口頭承諾。** 你最私密的文字（日記、信件、手稿）從不離開這台機器。沒有任何管線。
- **離線且恆久。** 無需網路、無需帳號，無論任何廠商如何變動都繼續運作。

### 用途說明

shelfseer 用來查詢**你擁有、或有權閱讀的文件** —— 你自己寫的東西、筆記與信件、公有領域作品，或你實際擁有的書。一切都在本機處理，不會上傳。請尊重著作權與作者、出版者的權利。

### 目前狀態

早期開發中。名字與概念已鎖定，實作尚未開始。進度請見本 repo。

### 授權

MIT —— 詳見 [LICENSE](LICENSE)。© 2026 CVER Inc.
