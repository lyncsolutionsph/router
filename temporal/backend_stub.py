from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import re

app = FastAPI(title="SEER Backend Stub")

# Allow all origins for local testing
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# In-memory device and policy storage
devices = [
    {"ip": "192.168.50.101", "hostname": "phone-joe", "mac": "AA:BB:CC:00:11:01", "uptime": 3600, "static": False, "interface": "lan0", "status": "active"},
    {"ip": "192.168.50.102", "hostname": "laptop-sara", "mac": "AA:BB:CC:00:11:02", "uptime": 7200, "static": False, "interface": "lan0", "status": "active"},
    {"ip": "192.168.50.1", "hostname": "board", "mac": "AA:BB:CC:00:11:FF", "uptime": 99999, "static": True, "interface": "wan0", "status": "active"}
]

policies: List[dict] = []
blocked_domains = set()

# Models
class PolicyIn(BaseModel):
    policy: Optional[str]
    source: Optional[str]
    destination: str
    schedule: Optional[dict] = None
    enabled: Optional[bool] = True

class TestIn(BaseModel):
    source: Optional[str]
    destination: str

# Helpers
_domain_re = re.compile(r"^(?:https?://)?(?:www\.)?([^/:]+)", re.IGNORECASE)

def normalize_domain(url: str) -> str:
    if not url:
        return ""
    m = _domain_re.match(url.strip())
    if m:
        return m.group(1).lower()
    return url.strip().lower()

def rebuild_blocked():
    global blocked_domains
    blocked_domains = set()
    for p in policies:
        if p.get("enabled") and p.get("destination"):
            blocked_domains.add(normalize_domain(p["destination"]))

# Endpoints
@app.get("/devices")
async def get_devices():
    return devices

@app.get("/policies")
async def get_policies():
    return policies

@app.post("/policies")
async def add_policy(p: PolicyIn):
    # If source empty, treat as board-wide
    src = p.source if p.source else "board"
    item = {
        "policy": p.policy or f"Block {p.destination}",
        "source": src,
        "destination": p.destination,
        "schedule": p.schedule or {"start": "00:00", "end": "23:59"},
        "enabled": p.enabled if p.enabled is not None else True
    }
    policies.append(item)
    rebuild_blocked()
    return {"status": "ok", "index": len(policies)-1}

@app.put("/policies/{index}")
async def update_policy(index: int, p: PolicyIn):
    if index < 0 or index >= len(policies):
        raise HTTPException(status_code=404, detail="Policy not found")
    src = p.source if p.source else "board"
    policies[index].update({
        "policy": p.policy or policies[index].get("policy"),
        "source": src,
        "destination": p.destination or policies[index].get("destination"),
        "schedule": p.schedule or policies[index].get("schedule"),
        "enabled": p.enabled if p.enabled is not None else policies[index].get("enabled", True)
    })
    rebuild_blocked()
    return {"status": "ok"}

@app.delete("/policies/{index}")
async def delete_policy(index: int):
    if index < 0 or index >= len(policies):
        raise HTTPException(status_code=404, detail="Policy not found")
    policies.pop(index)
    rebuild_blocked()
    return {"status": "ok"}

@app.post("/test")
async def test_policy(t: TestIn):
    # Normalize domain
    dest = normalize_domain(t.destination)
    # If blocked and applies to board or the specific source, consider the policy effective
    is_blocked = dest in blocked_domains
    applies_to_source = False
    if not is_blocked:
        return {"success": False, "reason": "not_blocked"}
    # If any enabled policy for this dest says source==board, or the provided source matches devices on board => applies
    for p in policies:
        if p.get("enabled") and normalize_domain(p.get("destination","")) == dest:
            if p.get("source") == "board":
                applies_to_source = True
                break
            # if the source IP is listed in devices and matches
            if t.source and any(d["ip"] == t.source for d in devices):
                applies_to_source = True
                break
    return {"success": applies_to_source}

@app.post("/reload")
async def reload_services():
    # For stub, just return ok. In a real system you'd trigger firewall/routing reload.
    return {"status": "reloaded"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend_stub:app", host="0.0.0.0", port=5000, reload=True)
