# Luffy Arm v1.8.0

The toolkit pins Luffy Arm to release v1.8.0, commit 12473f15f4c6026c631de143dd2b6a209788e464. Its product installer installs the core and ON/OFF companion skills together and removes obsolete product files. Server configuration, keys and session records remain outside the skill installation.

After updating the toolkit, run `git submodule update --init --recursive` and its installer for your chosen agent. To update only Luffy Arm, use `LUFFY_ARM_DIR=/path/to/skills bash skills/luffy-arm/install.sh`; this avoids changing unrelated skills or MCP configuration.

Register each server once:

```bash
luffy target add my-lab --params ~/.config/luffy-arm/params.sh --name "My lab"
luffy target add my-cluster --password --host login.example.org --user my-account --name "My cluster"
luffy target default my-lab
luffy tlist
luffy fullpower on my-lab 120000
luffy fullpower on my-cluster --password 120000
luffy fullpower status --all
luffy fullpower off --all
```

Key authentication may prompt for the private key's passphrase. Password authentication prompts inside OpenSSH. The human enters the secret; neither mode passes it to an agent. Password sessions detach after authentication. Repeated ON reuses the verified session/key and preserves its original expiry.

The default target is explicit when multiple servers are registered. Existing params-only commands still work before registration. Password sessions inherit personal-account permissions, rather than the optional cc ACL isolation. Host keys must already be trusted; no remote setup is performed by target registration.

Per-server skill entries can be thin local wrappers selecting a registered target ID and reading the shared Luffy Arm skill. Keep real server/account details local; they are not part of this toolkit.

[Release](https://github.com/Ares960826/luffy-arm/releases/tag/v1.8.0) · [Target grammar](https://github.com/Ares960826/luffy-arm/blob/v1.8.0/references/targets.md) · [Session lifecycle](https://github.com/Ares960826/luffy-arm/blob/v1.8.0/references/user-sessions.md)
