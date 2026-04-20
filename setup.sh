#!/bin/bash
# Run this once before starting any phase

echo ">>> Creating shared Docker network..."
docker network create infra 2>/dev/null || echo "Network 'infra' already exists"

echo ">>> Setting kernel params for SonarQube (Elasticsearch requirement)..."
sudo sysctl -w vm.max_map_count=524288
sudo sysctl -w fs.file-max=131072

echo ">>> Done. Now start phases:"
echo "  cd ~/infra-sim/phase1 && docker compose up -d"
echo "  cd ~/infra-sim/phase2 && docker compose up -d"
echo "  cd ~/infra-sim/phase3 && docker compose up -d"
echo "  cd ~/infra-sim/phase4 && docker compose up -d"
