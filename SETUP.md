# BeNeM — Developer Setup

## 1. Secrets Setup (`Secrets.swift`)

The app uses AES-256-GCM to decrypt credentials received via the `benem://` URL scheme.
The decryption key lives in `Secrets.swift`, which is **gitignored and must never be committed**.

### Steps

1. Copy the template:
   ```bash
   cp BeNeM/Secrets.swift.template BeNeM/Secrets.swift
   ```

2. Generate a 32-byte (64-char hex) key:
   ```bash
   python3 -c "import secrets; print(secrets.token_hex(32))"
   # or
   openssl rand -hex 32
   ```

3. Paste the key into `BeNeM/Secrets.swift`:
   ```swift
   enum Secrets {
       static let encryptionKey = "<your 64-char hex key here>"
   }
   ```

4. Add `Secrets.swift` to the Xcode project (target: BeNeM, compile sources).

5. Verify it's ignored by git:
   ```bash
   git status BeNeM/Secrets.swift   # should produce no output
   ```

> **Team note:** Every developer and CI machine must have their own `Secrets.swift`.
> Testers must receive links generated with the **same key** as the build installed on their device.
> Distributing a build with key A and links generated with key B will cause "Invalid Link" errors.

---

## 2. Python Link Generator

The `generate_benem_link.py` script creates `benem://` URLs for provisioning testers.

### Install dependency

```bash
pip install cryptography
```

### Set the secret key

```bash
export BENEM_SECRET_KEY=<the same 64-char hex key from your Secrets.swift>
```

Or copy `.env.template` to `.env`, fill it in, and source it:

```bash
cp .env.template .env
# edit .env
source .env   # or: export $(cat .env | xargs)
```

### Generate a link

```bash
# With PIN (SaaS servers):
python3 generate_benem_link.py \
  --server https://bhnm.example.com \
  --api_key YOUR_API_KEY \
  --pin YOUR_PIN \
  --user "John Smith"

# Without PIN (self-hosted servers):
python3 generate_benem_link.py \
  --server https://bhnm.example.com \
  --api_key YOUR_API_KEY \
  --user "John Smith"

# Without specifying user (defaults to "enter user name"):
python3 generate_benem_link.py \
  --server https://bhnm.example.com \
  --api_key YOUR_API_KEY
```

The script prints a single `benem://configure?...` URL. Send it to the tester via any channel
(email, Slack, AirDrop). The tester opens it on their device with BeNeM installed.

---

## 3. Security Notes

- `BENEM_SECRET_KEY` (and `Secrets.swift`) is equivalent to knowing the credentials in any link generated with that key.
- Without the correct `BENEM_SECRET_KEY`, no valid links can be generated and no links can be decrypted.
- The key should be rotated if it is ever exposed; all existing links will stop working after rotation.
- The key is stored as a string literal in the compiled binary. Running `strings BeNeM.app/BeNeM` can reveal it. This is acceptable for internal tester distribution; for public App Store builds, consider deriving the key at runtime.
