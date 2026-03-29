# HydraRoute Policy Inventory

This file captures the current effective selective-routing intent from HydraRoute so it can be migrated into a single `Xkeen`/`xray` routing model later.

## Current HydraRoute Mode

From `/opt/etc/HydraRoute/hrneo.conf`:

- `GlobalRouting=false`
- `DirectRouteEnabled=true`
- `PolicyOrder=HydraRoute`
- only domains listed in `domain.conf` are intended to go through proxy/VPN
- everything else is intended to stay direct

## Domain Inventory

Normalized from `/opt/etc/HydraRoute/domain.conf`.

### Proxy/VPN Domains

- `2ip.io`
- `2ip.ru`
- `4pda.to`
- `android.com`
- `anthropic.com`
- `appspot.com`
- `auth0.com`
- `cdn-telegram.org`
- `cdn.auth0.com`
- `cdninstagram.com`
- `chatgpt.com`
- `claude.ai`
- `claude.com`
- `claudeusercontent.com`
- `comments.app`
- `connect.facebook.net`
- `contest.com`
- `deepl.com`
- `dis.gd`
- `disboard.org`
- `discord-activities.com`
- `discord.center`
- `discord.co`
- `discord.com`
- `discord.design`
- `discord.dev`
- `discord.gg`
- `discord.gift`
- `discord.gifts`
- `discord.me`
- `discord.media`
- `discord.new`
- `discord.st`
- `discord.store`
- `discord.tools`
- `discord-attachments-uploads-prd.storage.googleapis.com`
- `discordactivities.com`
- `discordapp.com`
- `discordapp.io`
- `discordapp.net`
- `discordbee.com`
- `discordbotlist.com`
- `discordcdn.com`
- `discordexpert.com`
- `discordhome.com`
- `discordhub.com`
- `discordinvites.net`
- `discordlist.me`
- `discordlist.space`
- `discordmerch.com`
- `discordpartygames.com`
- `discords.com`
- `discordsays.com`
- `discordservers.com`
- `discordstatus.com`
- `discordtop.com`
- `disforge.com`
- `d.docs.live.net`
- `dyno.gg`
- `facebook.com`
- `fbcdn.net`
- `files.oaiusercontent.com`
- `findadiscord.com`
- `fragment.com`
- `ggpht.com`
- `google-analytics.com`
- `google.com`
- `googleapis.com`
- `googleusercontent.com`
- `googlevideo.com`
- `googlezip.net`
- `gpt3-openai.com`
- `graph.org`
- `gstatic.com`
- `gvt1.com`
- `gvt2.com`
- `gvt3.com`
- `httpbin.org`
- `ig.me`
- `instagram-p3-shv-01-hel3.fbcdn.com`
- `instagram.com`
- `intercom.io`
- `intercomcdn.com`
- `mee6.xyz`
- `mobile.events.data.microsoft.com`
- `my-od-1.wa.me`
- `my-od-2.wa.me`
- `my-od-3.wa.me`
- `my-od-4.wa.me`
- `my-od-5.wa.me`
- `my-od.wa.me`
- `nhacmp3youtube.com`
- `nnmclub.to`
- `oaistatic.com`
- `openai.com`
- `openai.fund`
- `openai.org`
- `pki.goog`
- `quiz.directory`
- `rutracker.org`
- `static.intercomassets.com`
- `t.me`
- `tdesktop.com`
- `telega.one`
- `telegra.ph`
- `telegram-cdn.org`
- `telegram.com`
- `telegram.dog`
- `telegram.me`
- `telegram.org`
- `telegram.space`
- `telesco.pe`
- `tg.dev`
- `top.gg`
- `turtlebeach.com`
- `tx.me`
- `usercontent.dev`
- `wa.me`
- `whatsapp.biz`
- `whatsapp.cc`
- `whatsapp.com`
- `whatsapp.fbsbx.com`
- `whatsapp.info`
- `whatsapp.net`
- `whatsapp.org`
- `whatsapp-plus.info`
- `whatsapp-plus.me`
- `whatsapp-plus.net`
- `whatsapp.tv`
- `whatsappbrand.com`
- `wl.co`
- `www.wa.me`
- `youtu.be`
- `youtube.com`
- `ytimg.com`

### Current Direct Exceptions Outside HydraRoute

These are already handled on the current router xray side and must not be forgotten during migration:

- `stalcraft.net`
- `exbo.net`
- `cdn77.org`

## Migration Intent

When moving to `Xkeen`, the clean target behavior is:

1. assign `Xkeen` policy to the selected device(s)
2. let `xray/Xkeen` receive the device traffic
3. route listed domains through `vless-reality`
4. route everything else to `direct`
5. keep explicit direct exceptions for `stalcraft.net`, `exbo.net`, `cdn77.org`

This reproduces the intent of the current HydraRoute setup without keeping HydraRoute in the final data path.
