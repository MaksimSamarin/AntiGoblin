# Инвентаризация политики HydraRoute

Этот файл фиксирует текущее фактическое намерение выборочной маршрутизации в `HydraRoute`, чтобы позже его можно было перенести в единую модель routing на `Xkeen`/`xray`.

## Текущий режим HydraRoute

Из `/opt/etc/HydraRoute/hrneo.conf`:

- `GlobalRouting=false`;
- `DirectRouteEnabled=true`;
- `PolicyOrder=HydraRoute`;
- через proxy/VPN должен идти только набор доменов из `domain.conf`;
- все остальное должно оставаться `direct`.

## Инвентаризация доменов

Нормализовано по `/opt/etc/HydraRoute/domain.conf`.

### Домены, которые должны идти через proxy/VPN

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

### Текущие direct-исключения вне HydraRoute

- `stalcraft.net`
- `exbo.net`
- `cdn77.org`

## Замысел миграции

Если в будущем логика будет переноситься целиком в `Xkeen`, то смысл этой политики такой:

1. назначить policy `xkeen` выбранным устройствам;
2. домены из списка выше направлять в VPN;
3. `stalcraft.net`, `exbo.net`, `cdn77.org` оставлять `direct`;
4. все остальное отправлять в `direct`.
