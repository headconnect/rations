# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 2.x.x   | :white_check_mark: |
| 1.x.x   | :x:                |

## Reporting a Vulnerability

Use [GitHub's private vulnerability reporting](https://github.com/headconnect/rations/security/advisories/new) to report a vulnerability. Please do not open a public issue for it.

## Scope

The primary vulnerabilities in scope here would be leakage of tokens from the keychain or logs, localhost callback accepting something that it shouldnt or being misdirected somehow, the opt-in usage hub answering anything beyond cached usage or being reachable from outside the machine, hijacked sign-in flows, update check manipulation, unwanted interaction with the host OS, etc. 

Basically - this tool is designed to just give an overview of the remaining usage for the AI subscriptions in scope. 

Anything that would allow others to misuse the credentials for any other purpose, or to direct the tool to use them for any other purpose, is very highly rated.

Causing rate limiting somehow from the upstream AI subscriptions is stuff that could get them annoyed at the user somehow, so that might also be in scope. 

Basically, this tool has a lot of potential power but should be very very limited in its operation, it's like having three loaded cannons and using them as paperweights. 

Unfortunately that's what it takes :) No more fine-grained tokens can be minted. 

## Bounties and such

There are none. There is no money in this, if it turns out that this thing is vulnerable beyond repair or if you intend to take it hostage or something - I'll just take the whole thing down and leave it to some other alternative :) 

Hopefully though there won't be anything too bad in this, and hopefully if there is it can be swiftly resolved. 

## My promise

I will respond in as timely a manner as I can. This is not my day job, I am probably the single maintainer, and I'm going to be trying to take some vacations completely offline from time to time. 

That being said, if you go three weeks without a response, please do feel free to write a Massive Warning in an issue and publicly disclose it so that people are aware. 

My priority is to the users and informing them when its likely that a vulnerability might be detected/exploited by others is just brilliant. 

You may also refer to this security guidance and recommend that the users uninstall the application until further notice. 
