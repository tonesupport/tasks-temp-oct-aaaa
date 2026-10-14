# Ground Truth Survey
## A Planning Scaffold for Getting Back In Control

**Date:** 260710  
**Status:** Draft — awaiting your annotations  
**How to use:** Read each section. Where you see a question or blank, add `{{your response}}` inline. When you're done with any section, say "proof [section name]" and I'll synthesize that into concrete next steps or a follow-up artifact.

You don't have to annotate everything at once. One section at a time is fine. The point is to get the map out of your head and into a file we can both work from.

---

## ORIENTATION

You asked for a map and a plan — a thing to wake up to. Before we can build that, we need to establish ground truth: what exists, where it lives, what's actually active vs. what's dead weight. This document is the diagnostic. What comes after it will be cleaner and smaller.

One important frame: from your Life Compass, the area with the **highest importance and lowest satisfaction across the board** is your self-actualization domain — work, learning, and creative practice. The one area that's actually going relatively well is your relationship with M. That's not nothing. We build from what's working.

Another frame: you described your brain as working like a filesystem. That's actually the right tool for this. The goal here is to give your mental filesystem a clean directory structure with nothing buried, nothing unnamed, and nothing co-habitating with things it shouldn't be co-habitating with.

---

## SECTION 1 — Named Systems Inventory

Everything you named, organized. Annotate anything that's wrong, missing, or more complicated than what I have here.

### 1.1 Environments / Machines

| Handle | What It Is | Current Status |
|--------|-----------|----------------|
| `zumaia` | DigitalOcean VPS (~$35/mo) — primary Linux dev environment | Active, expensive, underutilized? |
| `xafla` | Portable Windows/Git Bash env, designed to mirror zumaia | WIP / partial |
| `matia` | Local hard drive (Windows PC) | Filling up, Windows needs reinstall |
{{matia is an external hard drive, I have two laptops "strix" is my main editing machine, "ea" is a cf-31 toughbook that I use in the living room away from my workstation, mostly for job apps and reading etc..}}
| Codespaces | GitHub cloud dev environment | Being phased out? PDFs living there |
{{I don't know if it needs to be phased out entirely, but I defineitely can't use it in the way I 've been planning to use it as a replacement for zumaia}}
| iPad Pro (M1, 11") | Secondary device — Jump Desktop to Windows | Active | {{yes, and can be leveraged as a display etc.. when on couch or at strix}}
| WezTerm | Primary terminal emulator | Active |
{{I have a galaxy a9 tab which can be used in addition to or in place of the ipd for admin/display/info related tasks, etc.. I use spacedesk as a wired display driver to it. I use termux on it to ssh into zumaia occasionally and do that more if needed, but termux doesn't have the same customizability of wezterm, so generally prefer PCs even though less physically/spatially protable
my iphone 13 pro "longmont" despite being the main thing I make beats on via koala and a few auv3s is the absolute beign of my fucking existence both from a surveillance and dependency standpoint. i hate it. but i lready paid for it o it stays. I just hate integrating one off apps for it. those systems arent fucking sustainable.}}

---

### 1.2 Storage / Cloud

| Handle | What It Is | Current Status |
|--------|-----------|----------------|
| `tosu-space` | DigitalOcean Spaces bucket — deep storage | Active, accessed via Cyberduck |
| `upload-to-tosu-space` | Local staging folder for DO bucket uploads | "Overwhelmingly large" |
| Dropbox | 3.5TB, ~$40/mo | Want to migrate to tosu-space and cancel? |
{{ideally yes, or just cut that subscription down}}
| Codespaces | PDFs for guidebooks | Filling up, want to migrate | {{or just use in slimmer repo-specific fashion - I have a tendency to want to monorrepo everything thats in my head at a given time which fucks me up}}
| `matia` | Local drive backup | Filling up, needs sort | {{again, exteral}}

{{what's the approximate breakdown of what's in Dropbox? Is it mostly media/project files, or a mix of everything? Is there anything in Dropbox you actively access day-to-day? ... mix of everything, years of phone backups, personal photos, prject files, client work, apps, veryrhting has gotten shoved in there for ten years, most of the top level dirs won't even allow me to download them because they are too alrge and they can't be moved anywhere because the server times out or seomthing, generally though it contains a sync and an archive folder. sync is quick exchange between mahcine, archive is deep storage, inside of sync I have "desk" which contains "med" (medical), "fin" (financial), "ring" (passwords, etc.) - some portion of that is on zumaia/shelf (fin, ring, music, dev (job apps etc.)), but not all of it zo I need to go through and comprehensivekly figure it out - I have recently pulled shelf, tool, jig, knoll (my dotfiles), store, and tool (a shorthand for bin, but exists in different ways in multiple places - this backup is all debian binaries, but xafla for instance has its own tools - they are not identical, stencil (agent skills/context primers, etc.. but it's quite outdated relative the work I've been doing with traces in the codespace - which has two SKILL folders of its own))}}

{{is tosu-space already set up with a consistent naming/folder structure, or is it more of a flat dump?

tosu-space is:
sort
ether (misc)
keys (like ring but scattered)
moments (personal media)
projects (creative project files)
rafters (email and bookmarks archives)
snaps (assrted snapshots of above folders)
tools (again similar but scattered)}}



---

### 1.3 Active Projects

| Handle | What It Is | Repo Location | Status |
|--------|-----------|--------------|--------|
| `traces` | Browser-based live coding env — S7 Scheme + raylib | Unknown | Active, examples in progress |
| `guidebooks` | Longform academic reading project (codes, surfaces, patterns) | In traces repo? / Codespaces | Active, getting too big for traces repo |
| `codes` | Guidebook: handstyle via historical writing systems | — | Part dossiers in progress |
| `surfaces` | Guidebook: conceptual history of graphical/interface ideas | — | Part dossiers in progress |
| `patterns` | Sibling guidebook | — | Deferred | {{i folded patterns into codes I think - we dont really need the subprojects within guideboojs right now, just to treat it a its own unit}}
| `jib` | Utility scripts collection | — | Ongoing | {{its *jig}}
| `shelf` | Long-term deep storage (not the DO bucket — different?) | — | Ongoing | {{zumaia deep storage because fuck me}}
| `store` | Persistent admin resources | — | Ongoing |
| `dev` | Job application related stuff | — | Needs attention | {{ yes and my resume system itself is called "creds", dev tracks artefacts tht comwe from the pplication process and from creds}}
| `plat` | Large set of A/V applications directory | — | Status unknown | {{currently just loose on "strix", I should also mention that "tset" is my portable reasper installation where I reguarly backup my reaper config, and "dep" is all my plugins and plugin installers"}}
| `kits` | Sample storage / processing + sorting system | — | Ongoing, want to migrate to xafla |
| `demos` | Rough draft mixdown uploads | — | Ongoing |
| `beats` | Exported Ableton Live sets | — | Ongoing (new workflow, transitioning from Koala) |
| Koala | Mobile beat-making app | iPad + other devices | Active |
| `log/` | Static site / blog — generated via `haze.lua` | — | Active | {{yes, via hail.lua for text, haze.lua for images, and dub.lua for audio (generates a statoic bandcamp like thing - very new) - those are all scripts within log itself}}

{{is `shelf` something separate from tosu-space/DO bucket, or are they the same concept? I want to clarify whether "deep storage" means the DO bucket specifically or a broader concept including local archive dirs --- deep storage should mean something specific but to my mind it is currently a number of places, theres a shelf on zumaia, dropbox is treated as a shelf before i have the concept,theres a shelf on strix within sync - a fucking shitshow}}

{{where do guidebooks currently live —   its a subfolder inside the traces repo? it needs to get promoted to a thing of its own with its own location, ideally one that I can leverage froma  codespace though}}

{{is `jib` a specific repo, or more of a loose collection of scripts across environments? - again, *jig - it's just utility scripts}}

{{what's in `plat` approximately — is this like your VST/plugin installs, standalone media apps, or something else? it specifically things that arent plugins, like renoise installer, vcv rack portable installation, etc..}}

---

### 1.4 Day Job / Client Work

| System | What It Is | Current Issue |
|--------|-----------|--------------|
| Reaper | Daily driver audio editing | Need settings + project backup |
| DaVinci Resolve | Daily driver video editing | Need settings + project backup |
| Opus Clips | Short-form content suggestions / AI clip tool | 100GB storage exceeded, clips expiring |
| Invoice system | Hourly labor breakdown per episode | Messy — fixed-rate vs. actual-hours mismatch |
| Client relationship | Podcast audio/video edit + produce | Scope creep into marketing/retention |

{{just one client, one podcst with an audio feed and a video feed each with unique edits and the videos get a polished editied hook generated from opus}}

{{what does your current invoice process look like — spreadsheet, a doc you fill in manually, something else?}}

{{for Opus Clips — is that a client-required tool, or something you adopted independently? And is the 100GB cap a plan thing, or a hard account limit? --- client tool - I am basically being forced to use AI to replace myself - hence the need to look for a more sustainable vible career... after having built a small business over the course fo the last 6 years - fuck me}}

---

### 1.5 Personal / Household

| Domain | What It Is | Current Status |
|--------|-----------|--------------|
| M's injury | Wife is injured, needs physical therapy | Local PT spots booked 2-4 months out |
| NYC trip | Nate + Emily's wedding, end of September | Planning in progress |
| Weekly SOUs | State of the union meetings w/ M, tracked in Google Doc | Not well-translating to chore execution |
{{I should not ehtat I have huge issues with motiviation when it comes to household management and this a material way in which I could really help show I support M - she is the primary breadwinner, we sharef inances but on paper I'm the piece of shit below the poverty line - I qualified for Medical but M is doubtful that my legibility is legitimate -I've already been using it though, so need to get some legitness/in writing that they properly evaluated my tax household (of one - we file MFS - she's the one with the ful;l-time job)}}
| ITAA meetings | Internet/Technology Addiction Anonymous, 12-step | Attending regularly, haven't defined bottom/middle/top lines | {{fuck me - I do know that my "hopme" meeting at least is wednesdays at 12:30P - the ITAA+OCD meeting, but I'm also interested in regularly ttenfing the ITAA+Autism meeting which is weekly on friday at 3pm}}
| Hardware studio | Ongoing gear procurement (mostly private from M) | Overbought, underused, source of stress | {{ need to track returns, power supplies seem to missing from a few items, etc))}}
| Therapy | 2-4x/month | Working on Life Compass | {{generally have been going to the same therapist for about 4 years primarily for contamination OCD treated with iCBT (inference-based) but not it seems many of my symptoms have shifted to productivity and time OCD (procrastination, time perfection, missing details/scattered/dont know what to do with my life or how to train for it) I'm a fuck.}}

{{for the PT search — have you already tried a broader geographic radius, telehealth PT options, or asking M's GP for a direct referral? Sometimes a referral cuts the queue}} {{already tried broader geographic raius, have a consultation at Peak PT in Sonora 7/20 2:30p}}

{{for the NYC trip — is there anything concretely unfinished (flights, hotel, logistics) or is it more a feeling of "I thought I'd be further along in my life by now"? Both are valid but they need different responses --- haven't baought flight's, we;re attending staying in the same booking as our friends Leo and Torrie, need to coordinate flight times with them, etc. need to reach out asapo, will ikely get the second required booking on points}}



{{for ITAA — do you have a sponsor yet, and do you know enough about the program structure to identify what step you're on? Even if you haven't defined bottom/middle/top lines yet, knowing where you are in the step sequence might help -- they don't have consistent sponsors you can get a temporary sponsor for a week which I don't know what the fuck the point of thst would be -0 the while thing feels very abstract - either I have no idea what harm reduction looks like or I think most people are talking out of their asses becuse how could you not use a computer for the vast majority of tasks - I'm a fuck}}

---

### 1.6 Subscriptions (ongoing costs to audit)

| Service | ~Cost/mo | Purpose | Keep / Cut / Downgrade? |
|---------|---------|---------|------------------------|
| DigitalOcean VPS (zumaia) | ~$35 | Dev environment | {{?}} |
| Dropbox | ~$40 | Primary cloud storage | {{cut if tosu-space viable?}} |
| Opus Clips | Unknown | Short-form clip tool | {{?}} | {{covered by the client}}
| GitHub (Codespaces) | Unknown | Dev environment | {{phasing out?}} |
| DO Spaces (tosu-space) | Unknown | Deep storage bucket | Keep | {{included inn above 35}}
| ITAA | Free (12-step) | — | Keep | {{free}}
| Therapy | Copay | — | Keep | {{600/mo for M and I - we see the same one}}

{{are there other subscriptions I've missed — streaming, tools, memberships, etc.? --- yes, too many to count, don't know whow to get a handle on it or even figure that whole thing out}}

{{what's the total approximate monthly spend on tech subscriptions right now? -- seems like 2-300}}

---

## SECTION 2 — The Storage Architecture Problem

This is probably the most load-bearing issue because every other problem touches it. If storage is unclear, everything downstream is unclear.

### 2.1 What I understand to be true

You have roughly five "layers" of storage right now:

1. **Immediate working memory** — matia (local drive, filling up)
2. **Active project homes** — zumaia VPS, Codespaces (expensive, fragmented)
3. **Deep archive** — tosu-space DO bucket (good, but upload queue is a mess)
4. **Redundant cloud** — Dropbox 3.5TB (expensive, want to migrate out)
5. **Mobile/portable** — iPad, Koala exports

The problem isn't that you have too many storage locations — it's that there's **no clear intake path from working file → archive**, and nothing is consistently labeled, so things pile up in the upload staging folder and Dropbox instead of landing somewhere clean. {{basically yes, I have a mental model, but it is a katamari damacy mess of fuck because I'm a fuck with a shit for brain}}

### 2.2 Questions

{{what's the rough breakdown of what lives in the `upload-to-tosu-space` local staging folder — is it mostly old project exports, media files, random accumulation, or something else? -- very veyr new archive that exists primarily ot begun primarily so that I could freshly install windows on stric but everything has gotten stuck in the upload folder and my drive is too full to hve enough space to zip shit up in the way I want to, so it's just stcuk because I'm a fuck}}

{{do you currently have a naming convention for files and folders in tosu-space, or is it more of a "zip it and throw it in" situation? [YYMMDD-relevant-name.zip - could be better about it?]}}

{{is there a reason you're using the DO bucket specifically vs. something like Backblaze B2 (which is cheaper)? Is it proximity to zumaia, familiarity, or something else?  --- I was originally trying to bundle and port as many of my service subscription over to analogs on my DO account but I got stuck and now question the value of that pursuit - I don't mind continuing with the project5/intention but I'm a fuck}} 

{{when you say "pull down Dropbox, sort it, zip it, upload to tosu-space" — is the goal to completely cancel Dropbox? Or keep a smaller active tier there and archive the rest? -- as a first pass, smaller active tier}}

---

## SECTION 3 — The Project Scope Problem

You have roughly 12+ named active projects. Some of these are clearly different things (traces vs. guidebooks vs. dev). Others seem to be the same concept at different levels of abstraction (shelf vs. tosu-space). And some seem to have outgrown their original home (guidebooks inside traces repo).

{{I should mention here that most of my programming work and ongoing repos/projects exists in afolder called carve on zumaia which has just been backed up to local with the intention to crry over to xafla - but now I'm torn between going all in zumaia and/or backing up zumaia to xafla and using xafla sa the daily driver in order eliminate DO so nowe I'm confused because I'm a fuck}}

### 3.1 Project triage questions

{{for each of the following, rate them: HOT (active, needs attention now), WARM (ongoing but stable), COLD (deferred or deprioritized), DEAD (should formally retire)}}

- `traces` — {{HOT - actively developed, lives in codespaces, but codespaces in the way I'm using it isn't sustainable, the repo gets regualrly committed and synced to the giuthub remote though, but I need to clean up that tree cause guidebooks should be sepRATE - i PREFER TO USE gitbacked jj to begin with, so I have no allegiance to github and have a git forge via merveilles as well as a sourcehut account which I could use - I love sourcehut as a minimalist service - but it doesn't have shit the big boys do like "here's a free VPS with vsocde server go fuck yourself you fuck - be our slave you shit}}
- `guidebooks/codes` — {{- `guidebooks/surfaces` — {{}}
- `guidebooks/patterns` - WARM - just three of I think nine guidebooks, I'll go get tyhe tree of guidebooks rreal quick:

'!process'/   codes/   commands/   grammars/   markets/   readings/   sources/   structures/   surfaces/   symbols/   systems/   tools/

readings are primary sources, sources are secindary sources, process is claude skills and protocol documents, etc., each other folder is a guidebook - systems, grew out of traces as a sort of history of HCI with practical exampl projects (hypercard, engelbart, iverson, victor, ink and switch etc.. so it lived there but then as I accrued other guidebooks, it got out of hand to be within that repo - if I had infinite time - these books would be my lifes work - a shitty amazon self-published fuck of a don knuth-like shit that I ask to be buried with - alas, I've only been working on it for about a year - though traces has been conceived over the course of several - ask me for some documents on these to teach you waht they are, not that it matters because fuck-all) - they are huge massive reading lists nd drafted table of contents/writing prompts that would likely be 3-400 page books in and of themselves, I generally frame them as graduate-level reasearch in service of undergrad level text books and/or longform dissertation-level contemplations of HCI, codes is writing systems, grammars is formal grammars and PLT to an extent, marxist political though and marxist ecology, tools:## Instrumental Epistemology, Studio Practice, and Invention Ecology... if any can be promoted to a higher level of importance they are structures: HCI, permacomputing, assistive technology, and the politics of symbolic computing... systems: ## Design Theory, Notation, Liveness, and Programming Language Practice - basically what if bret victor wasn't an ivory tower fuck and dynamicland was opensource (even this book itself is conflated with structures itself) - I should have gone to CMU HCI but alas I live below the poverty line in rural middle of fuck nowhere california while my disable wife financiallly supports my disable ass - whose winning, me or the people who can apply to a job with any shred of hope? jurys out. shit.


}}
- `jig` — {{WARM/DEAD - disorganized - I use justfile to call into jog and it's al fucky cause I'm on many ssystems and the way it indexes through subcommands is fucking confusing because I have no willpower}}
- `shelf` — {{HOT - needs to be consoidated}}
- `store` — {{WARM}}
- `dev` (job applications) — {{DEAD, should be HOT because I'm a shit}}
- `plat` — {{just an archive to be carried over to the new strix install}}
- `kits` — {{bascially a huge folder of hundreds of saved koala kits that were then unzipped and stuffed into a reaper project, I still have both, but I would like to process ediot and sort all of the samples in that reaper project - just lack the time - it's totally uniomportant but still tkes up space in my head because I'm a piece of ADHD shit, foul, lower than the bacteria on taco bells toilet seat}}
- Koala beat workflow — {{gets way mor ttnetion thatn anything else because its the only thing that brings me some respite from my crippling depression}}
- Ableton workflow — {{barely begin, I have 12.4 suite, and my idea is to just carry around that installer and a very well organized user liubrary with all of my max devices, samples, etc.. but I haven't even begun that - I just hate all of the plugin dependendcuies of reaper - I've spent hundred of hours procurting and sporting plugin installers, trying to narrow down the bexst minimium viable set of plugins but it still leves me broken and trying to katamari roll an ecosystem and workflow out of fuck - I just like Reaper's level of cutomization - I have probably 200+ hours in my theme, custom actions, and keybinds because its helpful to an extent with dayjob but there are no inherently redeeming qualities of making art so I need to kill the part of my brain that has any intention of doing anything with my life besides working and doing shores because I'm a fuck - a distracted daydream-to-shit-fuck}}
- `log/` static site — {{HOT - five years of blog posts, should have more I never write enough and then when I do I forget to do the things I write about - I'm a disappointed independent scholar who should have stayed single, gotten a PhD and lived out of a $200 bsement in a major city with n active electronic music scene but instead I'm in the middle of no where and can barely take care of naything around me - let alone the love of my life - life happen because ... I'm a fuck}}
- xafla — {{was DEAD- should be HOT - in general, I'm sort of confused about direction - zumaia could be a daily driver and safe on a DO remote shard, or I could go local with xafla save a little bit of cash, but then eveyrhting needs to by backed up myself because I'm a fuck who still doesn't know how to program, I just pretend to know how because I'm on merveilles and I'm a fuck}}

---

### 3.2 The traces/guidebooks split

You noted that guidebooks "sort of came out of traces but is getting too big to keep in the traces repo." This is a repo boundary question. {{I expalion it above}}

{{is the connection between traces and guidebooks conceptual/thematic, or does guidebooks actually depend on traces code? In other words, is guidebooks a repo that happens to have been born inside traces, or does it import or use traces infrastructure? --- traces is the baseline/substrate computoing environment on which I would like to express ideas and PoCs and prototypes as I explore sturtcures and systems, right now it's basically an AI-fucked coderip of  lisp game jam - because I'm a fuck}} 

{{do you want guidebooks to become its own standalone repo with its own PDF reading workflow and staged architecture, entirely separate from traces? yes, it's time, I've pulled it locally to xafla, so subsequent work should be there or it should move to zumaia. zumaia only has I think 80- free gigs, and I imagine the pdfs should remain in the guidebook repos and theres something like 200 sources for each guidebook reading list, even though I really need to set up a system for pulling them all down, I've been using scite's MCP along with claude and gpt in the codespace to pull down the PDFs that are open access but I need an actual way to procure all of the sources on the list by *whatever menas accessibke to a remopte hosted bot with web access* - the pull down is a one time thing - once I have them, I can make guidebooks a self-contained offline project where I just read until I whither away on a sidewalk under a fucking piece of cardboard because I'm too afraid to share my goals and dreams with anyone including my wife because I'm a fuck}}

---

### 3.3 The `dev` (job application) situation

Your Life Compass gives Work/Career an importance of 2 and satisfaction of 0. You've noted it's "always behind, mismatched actions, everything overlaps." The `dev` folder exists but sounds underactive.

{{what does dev currently contain — is it a resume, cover letters, a list of target companies, notes, or mostly empty? each subdir in dev in a YYMMDD-employer_name-job_title that house a monolith html rip of the job descrip and all uploaded assets for tha pp, my resume is implemented in html using severl css libraries designed to make printing easier, I print through a browser and upload that, previous app dirs hold recommendtions, references, cover letters, etc.. but idwally I could port the whole thing to html or typst - but I haven';t because I'm a fuck}}

{{what kind of role are you primarily targeting right now — the tech-adjacent ones (solutions engineer, developer advocate, docs engineer, post-production coordinator) or something closer to your current edit/produce work? remind me to upload documents here - I've had lengthy conversations and plans drafrted with claude in other sessions but never any action taken because I'm fucking shit}}

{{what's the single biggest barrier to job applications right now — time, resume quality, not knowing where to apply, impostor syndrome, or something else? - cant do devrel because I don't know js, can't do devx because I've never been a dev, can't even get a fucking entry level deskjob in the middle of BFE california, so I don't know really - what I do know is that the job market has taught me that I'm a worthless piece of shit who shouldn't exist or waste the microjewels on formfills that nevert make it through ATS}}

---

## SECTION 4 — The Day Job Complexity Problem

You're being asked to do three jobs: edit, produce, and now effectively consult on content strategy/retention. That's a scope problem, not a skills problem.

### 4.1 Invoice / billing

{{your current invoicing situation — you bill a fixed number of duties per episode regardless of actual hours. Are you billing hourly or per-deliverable, and is the client's "hourly breakdown" request retroactively creating work you didn't track at the time?}}

{{what tool do you currently use to track time if at all — a spreadsheet, a text file, something else, or you don't?}}

{{do you have a standard episode rate, or does it vary? And is the fixed-duty billing something you set up, or something the client specified?}}

{{a n episode every week with fixed labor for each part of the process but I make it up as I go along because it's fucking stupid (and borderline uncalled for) to ask a 1099 employee for their timesheet nd I don't respect that request - ask me abiut this on the next round}}

### 4.2 Opus Clips / short-form storage

{{when clips expire from Opus Clips, are they actually gone — or are the source files (raw podcast recordings) still on your local drive or on Reaper/Resolve project storage? The question is whether expiration means data loss or just loss of the AI-processed version - I don't know - heklp me out here}}

{{is the client's use of Opus Clips something you're managing for them, or are they doing it themselves with files you provide? - I do it all myself, they just pay for the account - I process the full0length down into clips via opus, handpick viable opus gnerated clips and send off a half dozen in a bath to client, they pick the top 2-3, and I edit those into the hook for the fulllength - but the whole process is such a headache that it seems over half of my time is now devoted to this, and they want me to shift more and more labor away from the full-length edit and into the first 30 fucking seconds of what are mostly 90min episodes - because I'm a fuck and it's my fault for not having the means to leave - because like a fucking idiot - I have a mortgage now}}

{{for Resolve, the database and project files are in a separate Resolve database system. Do you know if you're running a local Resolve project database, or a disk database? This determines the backup strategy - no idea?? how do I check this - I'm so new to resolve despite having used it for several years, I'm the type of user who still identifies using a program at a beginner-level even after years because I'm a fuck-pilled fuck}}

### 4.3 Settings backup — Reaper + Resolve

{{do you know where Reaper's settings/theme/SWS/FX chain presets are stored on your Windows machine? This is typically `%APPDATA%\REAPER` — is that accessible? - I use a fully portable reaper instllation whose top level is called TSET - TSET is the equaivalent to REAPER resources folder.}}

{{for Resolve, the database and project files are in a separate Resolve database system. Do you know if you're running a local Resolve project database, or a disk database? This determines the backup strategy - no idea?? how do I check this - I'm so new to resolve despite having used it for several years, I'm the type of user who still identifies using a program at a beginner-level even after years because I'm a fuck-pilled fuck}}

---

## SECTION 5 — The Tech Infrastructure Problem

### 5.1 VPS (zumaia) vs. local (xafla)

You want to cut costs but you need a stable place to work. The tension is: zumaia is reliable but $35/mo and you're not using it fully. Codespaces is free-tier but filling up and unstable for your PDF workflow.

{{what do you actually use zumaia for day-to-day — is it mostly for running scripts, serving the static site, keeping a persistent shell session, or something else - I originally saw it as a way to roll my own sort of life-admin automation system via scripts - so I wouldn't have to use domwthing like zapier or n8 or whatever it's called but I don't have the skills to implement that so I just ask AI for a variety of scripts and then it puts me in more technical debt every day - so jig is a fuck and I am a fuck}}

{{is your log/ static site currently served from zumaia, or hosted elsewhere (GitHub Pages, Netlify, etc.)? It's served from DO via a git push trigger on commit - but I hate that because github wont host any of my images or audio/beats files so I need something else 0 I'm fine with hosting via DO and it's already setup with my domain etc. the github layer is a fuck becaause I'm a fuck}}

{{is VSCode Server something you want on zumaia (remote SSH into VPS from VSCode on Windows), or are you thinking of moving away from zumaia and running VSCode Server on a local machine? - I already have and use a local portable isntallation of vscode within xafla, but If I poorted this worfklwo to zumaia, then I would either want vscode-server or seomthing that isn't tmux. I literally just use vscode because I can drag and drop windows in a single nested interface, and even then it's a fuck because I'm still restrictred to a PC. I'm into vscode - but emrveilles hates vscode because it's an electron app which makes me a fuck.}}

### 5.2 Windows reinstall

{{what's preventing the Windows reinstall right now — specifically, is it that you haven't finished uploading matia to tosu-space, or that you're worried about losing specific app configurations, or both? strix C: isn't backed up yet, it's all in various stages of getting put on matia or tosu-space, and I can't keep trackof wahts where, or I did, but as tht project grew I lost track because I'm a fuck.}}

{{after reinstall, are you planning to set up xafla on the same Windows machine as the primary dev environment, essentially replacing zumaia for day-to-day shell work? that would be the use of xafla yes, I had a vision and somehwat of an AI-drafted plan for "harea" which is effectively managing everything as as portable debian qcow image using qemu for windows (portably) to launch  into the image with a daily backed-up overlay system, but I haven't gotten very far. I used VirtualBox perfectly for like a decade, but the minute I want to do something cool without a gui, I'm fucked.}}

### 5.3 Claude + ChatGPT conversation archive

{{do you have your ChatGPT data export already downloaded (Settings → Data Export)? It comes as a zip with JSON files - yeah, maybe not the last two weeks or so, but I have a relatively recent backup.}}

{{for Claude — have you tried the export feature in claude.ai settings, or are you looking for a way to convert both exports into a consistent, searchable format? no, I've never pulled ane xport from claude but I need to, I haveb een using gpt for like 4 years, nd calude for only a yearish}}

{{would a flat folder of markdown files (one per conversation) work for you, or do you need something with search/query capability? that works, but I'm actually thinking of something mroe akin to a repo of typst files that I can compile to a variety of formats, and then use html gen from typst or tinymist to generate an html archive and then add a searchability layer using hyperscript or htmx or somethin  (I don't even mind using js if it's quick enough to index something like a milllion words in a short length of time - I don't know how any of this works, nor have I ever attempted to designa  plan for this - but I would like to because much of my life has been conducted via AI chat over the last 2-3 years and I have accrused a serious knowledge base becauze I'm an incompetent fuck... and because modern web search is broken, but modtly because I'm a fuck)}}

---

## SECTION 6 — The Information Ecology Problem

You described reading Hacker News and lobste.rs "nearly obsessively even though none of that shit really applies to me." You're a member of Merveilles. You're attending ITAA. You're aware of the problem.

This isn't a tools problem. It's an appetite problem — but it has a tools component. {{no shit lol}}

### 6.1 ITAA ground work

The 12-step program requires defining:
- **Bottom lines**: behaviors you will not do (the "bottom" you're trying to avoid)
- **Middle lines**: behaviors that are warning signs or gray areas
- **Top lines**: the life you're trying to build (what sobriety looks like positively)

You haven't done this yet. That's okay — it's actually a significant amount of inner work and you're right that it takes time.

{{do you have a sponsor you're working with, or are you primarily attending meetings solo right now? ITAA doesn't offer sponsors long term - described above, but I regularly attend 2-4 meetings and its an extremely positive experience so far}}

{{if you were to take a first pass at a bottom line — just one, the most clear-cut behavior — what would it be? You don't have to solve the whole list, just one anchor point. ---- an all-nighter - I'm clean on all-nighters since march 15 though I can't idntify ways in which the problem has gotten ny better - I'm literally pouring my fucking heart and soul out to a corporate AI chatbot in the middle of a meeting}}

### 6.2 The Merveilles paradox

Merveilles is philosophically your people — permacomputing, anti-extractive tech, small tools, beautiful design. But it's also a source of scope creep (cf: designing a programming language on your iPad during your honeymoon).

{{is your Merveilles participation currently passive (reading), active (posting), or both? both}}

{{is there a specific project or direction you've encountered in Merveilles that genuinely serves your current goals vs. ones that are interesting but tangential? - it's rewarding and inspiring from a creative practice standpoint but a bit distracting from a being obsessed with symbolic manipulation but hving no skills to express my thoughts and notions there - I'm a fake and phony on that shit - but it's politically aligned, if I too could live on a sailboat, I would, but M and I are probably too disabled to do that.}}

---

## SECTION 7 — The Life Compass Translation

Based on what you filled out in your therapy compass, here's what I read:

**Highest importance, lowest satisfaction:**
- Work/Career (2/0) — "always behind, mismatched actions, everything overlaps"
- Education/Learning (2/0) — "I have little to no satisfaction with my self-actualization, want to do a million things at once" {{this is mostly guidebooks and traces}}
- Recreation/Leisure (2/0.5) — "definitely doing shit, but never going fast enough" {{this is mostly log and beats}}
- Friends/Social (1/0) — "I feel very lonely" {{ITAA is nice but I have no friends locally that aren't M's friends - I have people in merveilles I would maybe call friends but it feels so shallow - I see my closest friends who is a group of 4-6 guys I went to college with and their wonderful partners - this year it's Nate and Emily's wedding - I have no idea how to begin making local friends - up until march I was working about 60 hours a week between the podcast and managing a winery but only being paid as a tasting room associate - I was sacrificing sleep to get through the podcast workfload and have a little bit of time to spend with M but M got really worried about my mental health and basically gave me an ultimatum - pick one or the other - we chose to do the podcast and figure out how to get back to some more stable career. but I'm just in podcast and I'm a fuck-mode. no action anywhere else. but when I was at the winery I was able to mask sufficiently enough for a bit - and I'm pretty good at the customer service thing (I lead in sales, and made pretty decent tips) - interacting with strangers in a structured environment may be a strong suit but customer service doesn't pay enough for me to effectively contribute to the household - so I have to get a big boy job where I'm paid to hide my autism long enough to make it to the next day. I got along with a few people at work but others (as has historically been the case across jobs) a few always try to get me fired because they dont like me and sometime it works. the winery put me on a pip for some bullshit - almost nit-picking my above standard performance - I consitently was the only received postivie reviews online from customers - and I guess it made the others jealous or something - I'm just a fuck.}}
- Health (1/0) — "struggling with weight gain, anti-depressants make the copes hit less" {{the wellbutrin makes the off-brand gas station zyn hit less so I'm shoving chocolate cake and pizza and m&ms into my face in order to fit my old pants. 3 months ago I was 155 and gaunt - that was a low point where I ended up pulling an all-nighter and going missing for a day - our friend found me in the car - hence the "how are you going to turn your life round" conversation with M hence the ITAA and getting sleep, and eating, but I typically use diet purging and sleep deprivation as an internal motivator - if I'm too distracted to get anything done during the day, I can at least starve myself and read through the night enough to feel okay when the sun comes up but that's no longer a viable system.}}

**Going okay:**
- Romantic (3/1.5-2) — "something that's going right, continually getting better"
- Family (2/1) — "getting better," weekly dinners established
- Spirituality (0/2) — explicitly deprioritized, replaced with fiction + music

**Key tension:**  
You've defined yourself through your self-actualization (music, writing, research, code) — "this is how I define my self-actualization" — but you have zero satisfaction with it. Everything that matters most to you is where you feel most behind. That's an enormous amount of ambient grief and pressure.

{{does this read correctly to you? Is there anything here I'm mischaracterizing? NAIL ON THE HEAD MOTHERFUCKER}}

{{when you imagine "having your shit together" by the NYC trip in September — what does that specifically mean to you? Is it financial stability, a new job, the projects being organized, the house being in order, or some combination? having a job I like, supporting M, feeling the sensation of progress on seomthing outside of those (perhaps selfishly)}}

{{of all the domains above, if you could improve just ONE area's satisfaction score by end of September, which would you choose and why? increase job applications and/or persue resource directions, continue ITAA, - have some sense of direction}}

---

## SECTION 8 — The Hardware Studio

You mentioned overbought gear and that M doesn't fully know about all of it. This is sitting in the back somewhere.

{{roughly how much gear are we talking about — instruments, samplers, synthesizers, studio monitors, interfaces? I'm not asking for a dollar figure, just a sense of scope - I'm building an audio case and visual feedback case - having a hard time talking bout it - table it but keep it in the revision. I owe klarna some money with some number of zeroes. I never bought shit and was only in-the-box for about a decade and then something in me just snapped. --- this is what I mean when I say "rig" - it's an attmept to get off the computer to make art - but I can't do that because I'd have shit in the stu out of nowhere}}

{{is the plan to eventually build a dedicated home studio space, or to use it within existing space? - I have a dedicated space, but it's just a bunch of hidden gear in plastic boxes.}}

{{what would it take to feel like the studio was "set up" enough to actually use regularly — is it a space problem, a time problem, or a "need to finish xafla/ableton workflow first" problem? - a time and information problem - everything is a fuck - I can't tell anyone what I want to do - because I fear it will communicate that I don't want to work - but I've also been attributed with the "work addiction" label}}

---

## SECTION 9 — Proposed Sequencing (Provisional)

Based on everything above, here's my provisional read on what to prioritize, in rough order. Annotate agreement/disagreement.

### Tier 1 — Unblock the working environment (Week 1-2)

These are the things that are actively preventing everything else:

1. **Commit to the storage split**: zumaia for active development (or replace with VSCode Server on local), tosu-space for archive, let Dropbox migration be a 30-day project not an overnight one  
2. **Start a `matia-inventory.txt`** — a flat list of what's actually on the local drive, by folder, so we know what needs to move before the Windows reinstall  
3. **Move guidebooks out of traces repo** into its own standalone repo — this is blocking clean thinking about both projects {{done, it's in xafla - all of the importnt shiot from zumaia is in xafla so I can move forward with either - the most recent versions of log is in xafla - guidebooks inst on zumaia - otherwise rough parity I think}}

{{agree / disagree / modify?}}

### Tier 2 — Stabilize day job (Week 2-4)

4. **Invoice template** — build a simple, fixed template in Typst that you fill in each episode, with actual-hours tracking baked in going forward (even if retroactive is a mess)  
5. **Reaper + Resolve backup** — one-time backup of `%APPDATA%\REAPER` and Resolve database to tosu-space  
{{this is done - I have multiple versioned .Reaperconfiguration files backed up everywhere}}
6. **Opus Clips decision** — determine whether to downgrade/cancel and what the source file retention strategy is
{{fix this - I HAVE to use it}}
{{agree / disagree / modify?}}

### Tier 3 — Build the rhythm (Week 3-6)

7. **Define the `.tosu` task file structure** for daily use — one file, one day, what you're working on, nothing fancy  
8. **SOUs to actual checklist** — convert the Google Doc format into something that produces a concrete weekly task list for both you and M  
9. **First ITAA bottom line** — not the whole framework, just one anchor

{{agree / disagree / modify?}}

### Tier 4 — Longer-horizon projects (Month 2+)

10. **Dropbox migration** — iterative, not overnight  
11. **Windows reinstall** — after matia inventory complete and critical data in tosu-space  
12. **xafla build-out** — after Windows is clean  
13. **Job search reactivation** — structured sprint through `dev`  
14. **Ableton workflow** — after rig is packed + space is set

{{agree / disagree / modify? -- approximately correct - needs to be updated with above annotations}}

---

## SECTION 10 — What I Need From You

To move forward, the most useful things you can annotate are:

1. The project triage table in Section 3.1 — just HOT/WARM/COLD/DEAD for each
2. The storage questions in Section 2.2 — just quick answers
3. Section 9's tiers — quick agree/disagree/modify per tier

Everything else is optional for now. We'll build from whatever you give back.

---

## APPENDIX — Your Toolchain (as I understand it)

For reference when we build solutions:

- **Shell**: zsh {{unless xafla is the way}}
- **Terminal**: WezTerm
- **Editor**: VSCode (cloud), micro (terminal)
- **VCS**: `jj` (not git)
- **Task format**: `.tosu` (bracket sections, two-char sigils, custom calendar format)
- **Scripting**: Pluto (Lua superset) {{or tcl - I'm far more interested in tcl than Pluto - I just though pluto was the way}}
- **Data format**: TOML as source of truth
- **Build output**: static HTML/CSS
- **File manager**: yazi
- **Process runner**: just, supercronic
- **Env manager**: uv
- **CLI UX**: gum
- **Annotation protocol**: `{{double curly braces}}`
- **Output naming**: `YYMMDD-NNN-slug.md`

{{yeah,i guess}}

---

*End of ground truth survey. Return this file with annotations and I'll proof each section in turn.*
