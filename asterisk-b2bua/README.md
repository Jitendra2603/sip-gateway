# SIP Middleware Test Setup (GCP + Asterisk)

This deploys a public SIP middleware VM in `xi-playground` that:

- receives INVITEs from ElevenLabs SIP on `5060` (TCP by default)
- forwards calls to Twilio Elastic SIP Termination (TCP on `5060` by default)
- can optionally forward Twilio Origination calls back to ElevenLabs SIP
- anchors media on the middleware (`direct_media=no`) using RTP UDP `10000-20000`

## Deploy

From repo root:

```bash
chmod +x "tmp/sip-middleware/deploy-gcp-middleware.sh"
PROJECT_ID=xi-playground \
TWILIO_TERMINATION_HOST="replace-me.pstn.twilio.com" \
TWILIO_TERMINATION_PORT=5060 \
ELEVEN_ALLOW_CIDR="34.22.160.23/32" \
"tmp/sip-middleware/deploy-gcp-middleware.sh"
```

Optional auth for Twilio Termination:

```bash
PROJECT_ID=xi-playground \
TWILIO_TERMINATION_HOST="replace-me.pstn.twilio.com" \
TWILIO_USERNAME="your-termination-username" \
TWILIO_PASSWORD="your-termination-password" \
"tmp/sip-middleware/deploy-gcp-middleware.sh"
```

## On-Prem Deployment (Turkey / non-GCP)

Use this when you need the B2BUA physically hosted outside GCP (for example, in-country Turkey hosting).

### 1) Copy installer to the target host

```bash
scp "tmp/sip-middleware/install-onprem.sh" root@your-host:/tmp/
ssh root@your-host "chmod +x /tmp/install-onprem.sh"
```

### 2) Install and start middleware

```bash
ssh root@your-host "sudo /tmp/install-onprem.sh \
  --twilio-termination-host jitendra-test.pstn.twilio.com \
  --external-ip YOUR_PUBLIC_IP"
```

Optional auth hardening:

```bash
ssh root@your-host "sudo /tmp/install-onprem.sh \
  --twilio-termination-host jitendra-test.pstn.twilio.com \
  --external-ip YOUR_PUBLIC_IP \
  --twilio-username YOUR_TWILIO_USER \
  --twilio-password YOUR_TWILIO_PASS \
  --eleven-username YOUR_ELEVEN_USER \
  --eleven-password YOUR_ELEVEN_PASS \
  --eleven-allow-cidr 0.0.0.0/0"
```

### 3) Update config later without reinstall

On the host, edit:

- `/opt/sip-middleware/onprem.env`

Then re-render and restart:

```bash
sudo systemctl start sip-middleware-render.service
sudo docker exec sip-middleware asterisk -rx "pjsip show endpoints"
```

### 4) Required inbound ports

- TCP `5060` (SIP signaling)
- UDP `10000-20000` (RTP media)
- UDP `5060` optional compatibility path

Optional auth for inbound ElevenLabs -> middleware:

```bash
PROJECT_ID=xi-playground \
TWILIO_TERMINATION_HOST="your-trunk.pstn.twilio.com" \
ELEVEN_ALLOW_CIDR="0.0.0.0/0" \
ELEVEN_USERNAME="your-eleven-sip-user" \
ELEVEN_PASSWORD="your-eleven-sip-pass" \
"tmp/sip-middleware/deploy-gcp-middleware.sh"
```

Optional Twilio Origination -> Eleven forwarding:

```bash
PROJECT_ID=xi-playground \
TWILIO_TERMINATION_HOST="your-trunk.pstn.twilio.com" \
ELEVEN_FORWARD_HOST="your-eleven-sip-host-or-ip" \
ELEVEN_FORWARD_PORT=5060 \
"tmp/sip-middleware/deploy-gcp-middleware.sh"
```

## Update config after deploy

```bash
gcloud compute instances add-metadata "xi-sip-middleware-1" \
  --project "xi-playground" \
  --zone "us-central1-f" \
  --metadata "twilio_termination_host=your-trunk.pstn.twilio.com,twilio_termination_port=5060,eleven_allow_cidr=34.22.160.23/32,eleven_username=optional-eleven-user,eleven_password=optional-eleven-pass,eleven_forward_host=your-eleven-sip-host-or-ip,eleven_forward_port=5060"

gcloud compute ssh "xi-sip-middleware-1" \
  --project "xi-playground" \
  --zone "us-central1-f" \
  --tunnel-through-iap \
  --command "sudo systemctl start sip-middleware-render.service && sudo docker exec sip-middleware asterisk -rx 'pjsip show endpoints'"
```

## Twilio Elastic SIP config for end-to-end

For ElevenLabs -> Middleware -> Twilio outbound:

1. Twilio Console > Elastic SIP Trunk > your trunk > **Termination**
2. Set Termination URI host used in middleware metadata (`your-trunk.pstn.twilio.com`)
3. Authentication:
   - easiest: IP ACL allowing middleware public IP
   - or credentials + set `twilio_username` and `twilio_password` metadata
4. Caller ID and geo permissions according to your destination testing requirements

For Twilio -> Middleware origination testing:

1. Elastic SIP Trunk > **Origination** > add URI:
   - `sip:<middleware-public-ip>:5060;transport=udp`
2. Weight and priority as desired
3. Set middleware metadata `eleven_forward_host` to your ElevenLabs SIP host/IP
4. Re-render middleware config: `sudo systemctl start sip-middleware-render.service`

## ElevenLabs side

Set outbound SIP trunk `address` to middleware public IP and use transport `udp` or `tcp` on `5060`.

For IP allowlists, use CIDR `/32` for a single address (example: `35.225.73.132/32`).

## Open ports

- SIP signaling: TCP/UDP `5060` (and TCP `5061` opened)
- RTP media: UDP `10000-20000`

## Files

- `tmp/sip-middleware/deploy-gcp-middleware.sh` - GCP provisioning path
- `tmp/sip-middleware/startup-script.sh` - GCP VM bootstrap + Asterisk config render
- `tmp/sip-middleware/install-onprem.sh` - non-GCP host installer for same B2BUA flow
- `tmp/sip-middleware/onprem.env.example` - on-prem config template
