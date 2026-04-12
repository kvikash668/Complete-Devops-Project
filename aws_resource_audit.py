#!/usr/bin/env python3
"""
AWS Resource Auditor - Lists all key resources and monthly cost
Usage: python aws_audit.py [--region us-east-1]
"""

import boto3
import json
from datetime import datetime, date
import argparse

##################
##
### Install boto3 if needed
#  brew install python
#  pip3 install --upgrade pip
#  python3 --version
#  pip3 --version
#  python3 -m venv venv
#  source venv/bin/activate
#  pip install --upgrade pip
#  pip install boto3
#  python aws_audit.py
#  python aws_resource_audit.py
#  deactivate ##just run deactivate when done to exit virtual environment
#
# Scan all regions (slower but complete)
##python aws_audit.py
#
# Scan only common regions (faster)
##python aws_audit.py --quick
#
# Scan one specific region
##python aws_audit.py --region ap-south-1
##
#
#
#
#
##################
def get_regions(service="ec2"):
    ec2 = boto3.client("ec2", region_name="us-east-1")
    return [r["RegionName"] for r in ec2.describe_regions()["Regions"]]

def audit_ec2(region):
    ec2 = boto3.client("ec2", region_name=region)
    res = ec2.describe_instances()
    instances = []
    for r in res["Reservations"]:
        for i in r["Instances"]:
            name = next((t["Value"] for t in i.get("Tags", []) if t["Key"] == "Name"), "N/A")
            instances.append({
                "id": i["InstanceId"],
                "type": i["InstanceType"],
                "state": i["State"]["Name"],
                "name": name,
                "region": region
            })
    return instances

def audit_s3():
    s3 = boto3.client("s3")
    buckets = s3.list_buckets().get("Buckets", [])
    return [{"name": b["Name"], "created": str(b["CreationDate"].date())} for b in buckets]

def audit_rds(region):
    rds = boto3.client("rds", region_name=region)
    dbs = rds.describe_db_instances().get("DBInstances", [])
    return [{"id": d["DBInstanceIdentifier"], "class": d["DBInstanceClass"],
             "status": d["DBInstanceStatus"], "engine": d["Engine"], "region": region}
            for d in dbs]

def audit_lambda(region):
    lmb = boto3.client("lambda", region_name=region)
    fns = lmb.list_functions().get("Functions", [])
    return [{"name": f["FunctionName"], "runtime": f.get("Runtime","N/A"),
             "memory": f["MemorySize"], "region": region} for f in fns]

def audit_elastic_ips(region):
    ec2 = boto3.client("ec2", region_name=region)
    addrs = ec2.describe_addresses().get("Addresses", [])
    return [{"ip": a["PublicIp"],
             "attached": "Yes" if "AssociationId" in a else "NO - COSTS MONEY!",
             "region": region} for a in addrs]

def audit_nat_gateways(region):
    ec2 = boto3.client("ec2", region_name=region)
    nats = ec2.describe_nat_gateways().get("NatGateways", [])
    return [{"id": n["NatGatewayId"], "state": n["State"], "region": region}
            for n in nats if n["State"] != "deleted"]

def get_monthly_cost():
    ce = boto3.client("ce", region_name="us-east-1")
    today = date.today()
    start = today.replace(day=1).isoformat()
    end = today.isoformat()
    if start == end:  # first day of month edge case
        return []
    resp = ce.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="MONTHLY",
        Metrics=["BlendedCost"],
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}]
    )
    costs = []
    for g in resp["ResultsByTime"][0]["Groups"]:
        amount = float(g["Metrics"]["BlendedCost"]["Amount"])
        if amount > 0.001:
            costs.append({"service": g["Keys"][0], "cost_usd": round(amount, 4)})
    return sorted(costs, key=lambda x: x["cost_usd"], reverse=True)

def print_section(title, items, keys):
    print(f"\n{'='*60}")
    print(f"  {title} ({len(items)} found)")
    print('='*60)
    if not items:
        print("  None found.")
        return
    for item in items:
        print("  " + " | ".join(f"{k}: {item.get(k,'N/A')}" for k in keys))

def main():
    parser = argparse.ArgumentParser(description="AWS Resource Auditor")
    parser.add_argument("--region", help="Single region to scan (default: all regions)")
    parser.add_argument("--quick", action="store_true", help="Scan only us-east-1 and us-west-2")
    args = parser.parse_args()

    if args.region:
        regions = [args.region]
    elif args.quick:
        regions = ["us-east-1", "us-west-2", "ap-south-1"]
    else:
        print("Fetching all AWS regions...")
        regions = get_regions()

    print(f"\n🔍 AWS Resource Audit — {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print(f"Scanning {len(regions)} region(s): {', '.join(regions)}\n")

    all_ec2, all_rds, all_lambda, all_eips, all_nats = [], [], [], [], []

    for region in regions:
        print(f"  Scanning {region}...", end="\r")
        try:
            all_ec2    += audit_ec2(region)
            all_rds    += audit_rds(region)
            all_lambda += audit_lambda(region)
            all_eips   += audit_elastic_ips(region)
            all_nats   += audit_nat_gateways(region)
        except Exception as e:
            print(f"  ⚠ Skipped {region}: {e}")

    s3_buckets = audit_s3()

    # Print results
    print_section("EC2 Instances", all_ec2, ["region","id","name","type","state"])
    print_section("S3 Buckets", s3_buckets, ["name","created"])
    print_section("RDS Databases", all_rds, ["region","id","engine","class","status"])
    print_section("Lambda Functions", all_lambda, ["region","name","runtime","memory"])
    print_section("Elastic IPs", all_eips, ["region","ip","attached"])
    print_section("NAT Gateways", all_nats, ["region","id","state"])

    # Cost breakdown
    print(f"\n{'='*60}")
    print("  💰 Cost This Month (by Service)")
    print('='*60)
    try:
        costs = get_monthly_cost()
        total = sum(c["cost_usd"] for c in costs)
        for c in costs:
            bar = "█" * int(c["cost_usd"] / max(total, 1) * 30)
            print(f"  ${c['cost_usd']:>8.4f}  {bar}  {c['service']}")
        print(f"\n  TOTAL: ${total:.4f} USD this month")
    except Exception as e:
        print(f"  Could not fetch costs: {e}")
        print("  (Requires Cost Explorer enabled and ce:GetCostAndUsage permission)")

    print(f"\n{'='*60}\n")

if __name__ == "__main__":
    main()