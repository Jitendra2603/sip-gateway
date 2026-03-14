<p align="center">
  <img src="https://img.shields.io/badge/SIP-Gateway-blue?style=for-the-badge&logo=webrtc&logoColor=white" alt="SIP Gateway" />
</p>

<h1 align="center">SIP Gateway</h1>

<p align="center">
  Regional SIP gateway between ElevenLabs and customer SBCs — static IP, in-country presence, media anchoring.
</p>

<p align="center">
  <a href="#quick-start"><img src="https://img.shields.io/badge/get_started-→-green?style=flat-square" alt="Get Started" /></a>
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT License" />
  <img src="https://img.shields.io/badge/terraform-%3E%3D1.5-844FBA?style=flat-square&logo=terraform&logoColor=white" alt="Terraform >= 1.5" />
  <img src="https://img.shields.io/badge/docker-%3E%3D24.0-2496ED?style=flat-square&logo=docker&logoColor=white" alt="Docker >= 24.0" />
  <img src="https://img.shields.io/badge/kamailio-5.8-orange?style=flat-square" alt="Kamailio 5.8" />
  <img src="https://img.shields.io/badge/asterisk-latest-red?style=flat-square&logo=asterisk&logoColor=white" alt="Asterisk" />
  <img src="https://img.shields.io/badge/platform-GCP%20%7C%20on--prem-lightgrey?style=flat-square&logo=googlecloud&logoColor=white" alt="GCP | On-Prem" />
</p>

---

## Problem

```mermaid
graph LR
    LK[ElevenLabs SIP] -.->|"❌ Dynamic IPs<br/>❌ Outside country<br/>❌ No FQDN support"| SBC[Customer SBC]
    style LK fill:#fee,stroke:#c33
    style SBC fill:#fee,stroke:#c33
```

| Issue | Impact |
|-------|--------|
| SIP server IPs are dynamic | Legacy SBCs (Five9, etc.) can't whitelist |
| SIP INVITE originates outside country | Blocked by local telecom regulators (e.g., Turkey) |
| SBC requires IP, not FQDN | Direct connection impossible |

## Solution

```mermaid
graph LR
    LK[ElevenLabs SIP] -->|TCP 5060| GW["<b>SIP Gateway</b><br/>Static IP • In-Region"]
    GW -->|SIP + RTP| SBC[Customer SBC / Twilio]
    style GW fill:#dfd,stroke:#0a0,stroke-width:2px
```

Deploy a lightweight SIP gateway in any region. It provides a **fixed IP**, **in-country presence**, and **media anchoring** — all RTP audio flows through it.

---

## Two Approaches

<table>
<tr>
<td width="50%" valign="top">

### 🔹 [Kamailio + RTPEngine](./kamailio-proxy/)

**Stateful SIP proxy** with dedicated media relay.

- ~2ms overhead per call
- ~1000+ concurrent calls
- Automatic header passthrough
- Zero-copy RTP forwarding
- **Best for:** production, high scale, transparent relay

</td>
<td width="50%" valign="top">

### 🔸 [Asterisk B2BUA](./asterisk-b2bua/)

**Full Back-to-Back User Agent** (PBX engine).

- Full codec transcoding support
- IVR, DTMF, call recording at the gateway
- Asterisk dialplan flexibility
- **Best for:** PoC, when you need call logic at the edge

</td>
</tr>
</table>

### Comparison

| | Kamailio + RTPEngine | Asterisk B2BUA |
|---|:---:|:---:|
| **Latency** | ~2ms | ~10-20ms |
| **Max concurrent calls** | 1000+ | 50-100 |
| **Header passthrough** | Automatic | Explicit mapping |
| **Codec transcoding** | ✗ | ✓ |
| **IVR / call logic** | ✗ | ✓ |
| **SIP dialog** | Preserved (proxy) | Re-originated (B2BUA) |
| **Config complexity** | ~150 lines | ~200 lines |

### Which one?

```mermaid
flowchart TD
    A{"Need transcoding, IVR,<br/>or recording at gateway?"} -->|Yes| B["<b>Asterisk B2BUA</b>"]
    A -->|No| C{"Need >100<br/>concurrent calls?"}
    C -->|Yes| D["<b>Kamailio + RTPEngine</b>"]
    C -->|No| E["Either works — Kamailio<br/>is lighter for pure relay"]
    style B fill:#ddf,stroke:#33a
    style D fill:#dfd,stroke:#0a0
```

---

## Call Flow

```mermaid
sequenceDiagram
    participant EL as ElevenLabs SIP
    participant GW as SIP Gateway
    participant SBC as Customer SBC

    EL->>GW: INVITE sip:+1234@gateway:5060
    Note over GW: Rewrite R-URI → customer SBC<br/>Anchor media (RTPEngine/Asterisk)
    GW->>SBC: INVITE sip:+1234@sbc.customer.com
    SBC-->>GW: 100 Trying
    GW-->>EL: 100 Trying
    SBC-->>GW: 180 Ringing
    GW-->>EL: 180 Ringing
    SBC-->>GW: 200 OK (SDP: SBC media IP)
    Note over GW: Rewrite SDP → gateway IP
    GW-->>EL: 200 OK (SDP: gateway IP)
    EL->>GW: ACK

    rect rgb(240, 255, 240)
        Note over EL,SBC: 🔊 RTP audio flows through gateway
        EL->>GW: RTP (UDP)
        GW->>SBC: RTP (UDP)
        SBC->>GW: RTP
        GW->>EL: RTP
    end

    SBC->>GW: BYE
    GW->>EL: BYE
```

---

## Quick Start

### GCP Deployment

<details>
<summary><b>Kamailio + RTPEngine</b></summary>

```bash
cd kamailio-proxy/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit region, zone, project

terraform init && terraform apply

cd ../scripts
./deploy.sh --customer-sbc your-trunk.pstn.twilio.com
```

</details>

<details>
<summary><b>Asterisk B2BUA</b></summary>

```bash
cd asterisk-b2bua
PROJECT_ID=your-project \
TWILIO_TERMINATION_HOST="your-trunk.pstn.twilio.com" \
bash deploy-gcp-middleware.sh
```

</details>

### On-Prem / Non-GCP (Turkey, etc.)

<details>
<summary><b>Kamailio + RTPEngine</b></summary>

```bash
sudo bash kamailio-proxy/scripts/install-onprem.sh \
    --external-ip <PUBLIC_IP> \
    --internal-ip <PRIVATE_IP> \
    --customer-sbc your-trunk.pstn.twilio.com
```

</details>

<details>
<summary><b>Asterisk B2BUA</b></summary>

```bash
sudo bash asterisk-b2bua/install-onprem.sh \
    --twilio-termination-host your-trunk.pstn.twilio.com \
    --external-ip <PUBLIC_IP>
```

</details>

Both scripts install Docker, write all configs, open firewall ports, and start the stack.

---

## ElevenLabs Configuration

After deploying, configure the outbound trunk:

| Field | Value |
|-------|-------|
| **Address** | `<gateway-ip>` |
| **Transport** | TCP |
| **Auth** | Username/password (if enabled) |

## Twilio Elastic SIP

| Direction | Configuration |
|-----------|---------------|
| **Termination** (outbound) | Add `<gateway-ip>/32` to IP Access Control List |
| **Origination** (inbound) | Add URI `sip:<gateway-ip>:5060;transport=tcp` |

---

## Requirements

| Resource | Minimum |
|----------|---------|
| **OS** | Ubuntu 22.04+, Debian 12+, CentOS 8+ |
| **CPU** | 2 cores |
| **RAM** | 2 GB |
| **Ports** | TCP 5060, UDP 5060, UDP 10000-20000 |
| **IP** | Static public IP (or NAT with port forwarding) |

---

## Project Structure

```
sip-gateway/
├── kamailio-proxy/              # Kamailio + RTPEngine
│   ├── docker/                  #   Docker Compose stack
│   ├── terraform/               #   GCP infrastructure
│   ├── scripts/                 #   Deploy + on-prem installer
│   └── README.md
├── asterisk-b2bua/              # Asterisk B2BUA
│   ├── deploy-gcp-middleware.sh #   GCP provisioning
│   ├── install-onprem.sh        #   On-prem installer
│   ├── startup-script.sh        #   VM bootstrap
│   └── README.md
└── README.md                    # This file
```
---

## License

MIT

---

<p align="center">
  <sub>Built for <a href="https://elevenlabs.io">ElevenLabs</a> Conversational AI telephony</sub>
</p>
