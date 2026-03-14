# SIP Gateway

A regional SIP gateway (Kamailio + RTPEngine) that sits between the LiveKit SIP server and a customer's SBC, providing:

1. **Static IP** — customers can whitelist a single IP (solves the LiveKit Cloud dynamic-IP problem for legacy SBCs like Five9)
2. **Regional presence** — SIP INVITEs originate from within a specific country/region (solves regulatory requirements like Turkey's ban on foreign-origin SIP)
3. **Media anchoring** — all RTP/audio flows through the gateway, so the customer only needs to peer with one IP

## Architecture

```
┌──────────────┐     SIP INVITE      ┌──────────────────┐     SIP INVITE      ┌──────────────┐
│              │  ──────────────────► │                  │  ──────────────────► │              │
│  LiveKit SIP │                      │   SIP Gateway    │                      │ Customer SBC │
│    Server    │  ◄────────────────── │  (Kamailio +     │  ◄────────────────── │              │
│              │     SIP Responses    │   RTPEngine)     │     SIP Responses    │              │
└──────┬───────┘                      └────────┬─────────┘                      └──────┬───────┘
       │                                       │                                       │
       │            RTP Audio (UDP)             │            RTP Audio (UDP)             │
       └───────────────────────────────────────►├──────────────────────────────────────►│
       ◄────────────────────────────────────────┤◄─────────────────────────────────────┘
```

The gateway is transparent — LiveKit SIP sends an INVITE to the gateway IP, Kamailio rewrites the destination to the customer's SBC, and RTPEngine anchors all media through the gateway's public IP.

## Use Cases

| Problem | Solution |
|---------|----------|
| Turkey regulatory: SIP INVITE must originate within Turkey | Deploy gateway on a Turkish host |
| Five9 / legacy SBC requires IP whitelisting | Gateway provides a single static IP |
| Customer SBC doesn't support FQDN | Gateway exposes a fixed IP address |
| Need media to flow through a specific region | RTPEngine anchors RTP in-region |

## Components

| Component | Role | Ports |
|-----------|------|-------|
| **Kamailio** | SIP signaling proxy — receives INVITEs, rewrites headers, relays to customer SBC | UDP/TCP 5060, TCP 5061 |
| **RTPEngine** | Media relay — rewrites SDP, proxies RTP/RTCP streams | UDP 10000-20000 |

## Quick Start

### Prerequisites

- `gcloud` CLI authenticated to `xi-playground`
- Terraform >= 1.5
- A customer SBC address to forward to

### 1. Provision infrastructure

```bash
cd infra/sip-gateway/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set region, zone, etc.

terraform init
terraform plan
terraform apply
```

This creates:
- GCE VM with Container-Optimized OS
- Static external IP
- Firewall rules for SIP (5060), RTP (10000-20000), SSH

Note the output `sip_gateway_static_ip` — this is the IP customers will whitelist.

### 2. Deploy the SIP gateway stack

```bash
cd infra/sip-gateway/scripts
./deploy.sh --customer-sbc sbc.customer.com --customer-sbc-port 5060
```

This copies the Docker Compose stack to the VM, configures it, and starts Kamailio + RTPEngine.

### 3. Configure LiveKit outbound trunk

Point the LiveKit outbound trunk's `address` to the gateway instead of the customer's SBC directly:

```python
# Before (direct to customer SBC):
SIPOutboundTrunkConfig(
    address="sbc.customer.com",
    ...
)

# After (through gateway):
SIPOutboundTrunkConfig(
    address="<sip-gateway-static-ip>",
    ...
)
```

Or via the LiveKit API:
```json
{
  "trunk": {
    "name": "Customer via SIP Gateway",
    "address": "<sip-gateway-static-ip>:5060",
    "numbers": ["+15105550100"],
    "authUsername": "<username>",
    "authPassword": "<password>"
  }
}
```

The gateway transparently forwards the INVITE to the customer SBC configured in its `.env`.

### 4. Smoke test

```bash
./scripts/test-sip.sh <sip-gateway-static-ip>
```

## On-Prem / Non-GCP Deployment (Turkey, etc.)

GCP does not have a Turkey region (announced late 2025, no launch date). For in-country
regulatory compliance, deploy on a local host — any Linux server with a public IP works.

### One-liner install

SSH into the target host and run:

```bash
sudo bash install-onprem.sh \
    --external-ip 203.0.113.50 \
    --internal-ip 10.0.0.5 \
    --customer-sbc sbc.customer.com \
    --customer-sbc-port 5060
```

Or copy the script from this repo:

```bash
scp scripts/install-onprem.sh root@turkish-host:/tmp/
ssh root@turkish-host 'bash /tmp/install-onprem.sh \
    --external-ip 203.0.113.50 \
    --internal-ip 10.0.0.5 \
    --customer-sbc sbc.customer.com'
```

The script:
1. Installs Docker (Debian/Ubuntu/CentOS)
2. Writes all config files (Kamailio, RTPEngine, docker-compose)
3. Opens firewall ports (ufw or firewalld)
4. Builds and starts the stack

### With auth enabled

```bash
sudo bash install-onprem.sh \
    --external-ip 203.0.113.50 \
    --internal-ip 10.0.0.5 \
    --customer-sbc sbc.customer.com \
    --auth-user elevenlabs \
    --auth-password 'SomeSecurePassword'
```

Then in the Kamailio config at `/opt/sip-gateway/docker/kamailio/kamailio.cfg`,
uncomment the `# route(AUTH);` line and restart:

```bash
docker compose -f /opt/sip-gateway/docker/docker-compose.yml restart kamailio
```

### No NAT (public IP directly on interface)

If the host has the public IP assigned directly (no NAT), pass the same IP for both:

```bash
sudo bash install-onprem.sh \
    --external-ip 203.0.113.50 \
    --internal-ip 203.0.113.50 \
    --customer-sbc sbc.customer.com
```

### Behind NAT / router

If the host is behind a NAT router, configure port forwarding on the router:

| Protocol | External Port | Internal Target |
|----------|--------------|-----------------|
| TCP | 5060 | `<internal-ip>:5060` |
| UDP | 5060 | `<internal-ip>:5060` |
| UDP | 10000-20000 | `<internal-ip>:10000-20000` |

### Recommended Turkish hosting providers

| Provider | Notes |
|----------|-------|
| [Turkcell Cloud](https://bulut.turkcell.com.tr) | Largest Turkish cloud, Istanbul DCs |
| [Hetzner](https://www.hetzner.com) | Has Istanbul PoP via Hetzner Cloud |
| Any Turkish colo/VPS | Bare metal with public IP works fine |

### Requirements

- Linux (Ubuntu 22.04+, Debian 12+, CentOS 8+)
- 2 CPU cores, 2GB RAM minimum
- Public IP (static preferred)
- Ports open: TCP 5060, UDP 5060, UDP 10000-20000

### GCP alternatives (nearest regions)

If in-country isn't strictly required, nearest GCP regions:

| Region | Location | Distance to Istanbul |
|--------|----------|---------------------|
| `europe-west1` | Belgium | ~2000km |
| `europe-west3` | Frankfurt | ~1800km |
| `me-west1` | Tel Aviv | ~1100km |

## Operations

### View logs
```bash
gcloud compute ssh sip-gateway --project=xi-playground --zone=europe-west1-b \
    --command='sudo docker compose -f /opt/sip-gateway/docker/docker-compose.yml logs -f'
```

### Restart stack
```bash
gcloud compute ssh sip-gateway --project=xi-playground --zone=europe-west1-b \
    --command='sudo docker compose -f /opt/sip-gateway/docker/docker-compose.yml restart'
```

### Update customer SBC address
```bash
gcloud compute ssh sip-gateway --project=xi-playground --zone=europe-west1-b \
    --command="sed -i 's/^CUSTOMER_SBC_ADDRESS=.*/CUSTOMER_SBC_ADDRESS=new-sbc.customer.com/' /opt/sip-gateway/.env && sudo docker compose -f /opt/sip-gateway/docker/docker-compose.yml restart kamailio"
```

### Check RTPEngine stats
```bash
gcloud compute ssh sip-gateway --project=xi-playground --zone=europe-west1-b \
    --command='sudo docker exec sip-gateway-rtpengine rtpengine-ctl list sessions'
```

## How the Call Flow Works (Detail)

1. **Backend calls LiveKit API** — `CreateSIPParticipant` with the outbound trunk that points to the gateway
2. **LiveKit SIP server sends INVITE** — to `<gateway-ip>:5060` with the destination number in the R-URI
3. **Kamailio receives INVITE** — rewrites R-URI to `sip:<number>@<customer-sbc>:5060`
4. **RTPEngine rewrites SDP** — replaces the media IP in the SDP with the gateway's public IP
5. **Kamailio forwards INVITE** — to the customer's SBC
6. **Customer SBC responds** — 100 Trying, 180 Ringing, 200 OK
7. **Kamailio relays responses** — back to LiveKit SIP, RTPEngine rewrites SDP in responses too
8. **RTP flows** — LiveKit ↔ RTPEngine ↔ Customer SBC (all through the gateway's public IP)
9. **BYE** — either side hangs up, Kamailio relays, RTPEngine cleans up the media session

## Multi-Tenant Extension

The current setup is single-tenant (one customer SBC per gateway). To support multiple customers:

1. **Use custom SIP headers** — LiveKit can send custom headers via `CreateSIPParticipant`. Kamailio can read a header like `X-SBC-Address` to determine the destination.
2. **Use a database** — Kamailio can look up routing by the From number or a custom header in a database.
3. **Multiple outbound trunks** — each LiveKit outbound trunk points to the same gateway but with different SIP headers.

## File Structure

```
infra/sip-gateway/
├── terraform/
│   ├── main.tf                  # GCE VM, static IP, firewall rules
│   ├── variables.tf             # Configurable parameters
│   ├── outputs.tf               # Static IP, SIP URI
│   └── terraform.tfvars.example # Example configuration
├── docker/
│   ├── docker-compose.yml       # Kamailio + RTPEngine stack
│   ├── .env.example             # Environment template
│   ├── kamailio/
│   │   ├── Dockerfile
│   │   └── kamailio.cfg         # SIP routing configuration
│   └── rtpengine/
│       └── Dockerfile
├── scripts/
│   ├── startup.sh               # GCE startup script
│   ├── deploy.sh                # Deploy stack to GCE instance
│   ├── install-onprem.sh        # Self-contained on-prem/non-GCP installer
│   └── test-sip.sh              # SIP OPTIONS smoke test
└── README.md
```
