#!/bin/bash
DEVOPS_URL=$1
PAT_TOKEN=$2
VM_NAME=$3
AGENT_COUNT=$4
AGENT_POOL=$5
AGENT_USER="azagent"
LOG_FILE="/var/log/install-agents.log"

echo "$(date) - Starting script" | sudo tee -a "$LOG_FILE"

# Instalace závislostí pro RHEL 9
sudo dnf update -y 2>&1 | sudo tee -a "$LOG_FILE"
sudo dnf install -y curl unzip libicu 2>&1 | sudo tee -a "$LOG_FILE"

# Vytvoření uživatele azagent, pokud neexistuje
if ! id "$AGENT_USER" >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash "$AGENT_USER" 2>&1 | sudo tee -a "$LOG_FILE"
  echo "$(date) - Uživatel $AGENT_USER vytvořen" | sudo tee -a "$LOG_FILE"
else
  echo "$(date) - Uživatel $AGENT_USER již existuje" | sudo tee -a "$LOG_FILE"
fi

# Stažení agenta do dočasného adresáře
echo "$(date) - Stahování agenta" | sudo tee -a "$LOG_FILE"
curl -L https://vstsagentpackage.azureedge.net/agent/3.220.0/vsts-agent-linux-x64-3.220.0.tar.gz -o /tmp/agent.tar.gz 2>&1 | sudo tee -a "$LOG_FILE"
if [ $? -ne 0 ] || [ ! -f "/tmp/agent.tar.gz" ]; then
  echo "$(date) - Chyba: Stažení agenta selhalo nebo soubor nenalezen" | sudo tee -a "$LOG_FILE"
  exit 1
fi
echo "$(date) - Agent úspěšně stažen: $(ls -l /tmp/agent.tar.gz)" | sudo tee -a "$LOG_FILE"

# Instalace a konfigurace více agentů
for i in $(seq 1 $AGENT_COUNT); do
  AGENT_NAME="${VM_NAME}-agent${i}"
  AGENT_DIR="/home/$AGENT_USER/myagent${i}"

  echo "$(date) - Instalace agenta $AGENT_NAME do $AGENT_DIR" | sudo tee -a "$LOG_FILE"

  # Vytvoření adresáře a nastavení vlastníka
  sudo mkdir -p "$AGENT_DIR" 2>&1 | sudo tee -a "$LOG_FILE"
  sudo chown "$AGENT_USER:$AGENT_USER" "$AGENT_DIR" 2>&1 | sudo tee -a "$LOG_FILE"
  echo "$(date) - Adresář $AGENT_DIR vytvořen a nastaven pro $AGENT_USER" | sudo tee -a "$LOG_FILE"

  # Kopie a rozbalení agenta
  echo "$(date) - Kopírování agenta do $AGENT_DIR" | sudo tee -a "$LOG_FILE"
  sudo -u "$AGENT_USER" bash -c "cp /tmp/agent.tar.gz $AGENT_DIR/" 2>&1 | sudo tee -a "$LOG_FILE"
  if [ ! -f "$AGENT_DIR/agent.tar.gz" ]; then
    echo "$(date) - Chyba: agent.tar.gz nebyl zkopírován do $AGENT_DIR" | sudo tee -a "$LOG_FILE"
    exit 1
  fi

  echo "$(date) - Rozbalování agenta v $AGENT_DIR" | sudo tee -a "$LOG_FILE"
  sudo -u "$AGENT_USER" bash -c "cd $AGENT_DIR && tar -xzf agent.tar.gz" 2>&1 | sudo tee -a "$LOG_FILE"
  if [ $? -ne 0 ] || [ ! -f "$AGENT_DIR/svc.sh" ]; then
    echo "$(date) - Chyba: Rozbalení selhalo nebo svc.sh nenalezen v $AGENT_DIR" | sudo tee -a "$LOG_FILE"
    echo "$(date) - Obsah $AGENT_DIR: $(ls -l $AGENT_DIR)" | sudo tee -a "$LOG_FILE"
    exit 1
  fi
  echo "$(date) - Agent úspěšně rozbalen v $AGENT_DIR" | sudo tee -a "$LOG_FILE"

  # Konfigurace agenta
  sudo -u "$AGENT_USER" bash -c "cd $AGENT_DIR && ./config.sh --unattended \
    --url '$DEVOPS_URL' \
    --auth pat \
    --token '$PAT_TOKEN' \
    --pool '$AGENT_POOL' \
    --agent '$AGENT_NAME' \
    --acceptTeeEula" 2>&1 | sudo tee -a "$LOG_FILE"

  # Kontrola existence svc.sh před instalací služby
  if [ -f "$AGENT_DIR/svc.sh" ]; then
    sudo bash -c "cd $AGENT_DIR && ./svc.sh install $AGENT_USER" 2>&1 | sudo tee -a "$LOG_FILE"
    sudo bash -c "cd $AGENT_DIR && ./svc.sh start" 2>&1 | sudo tee -a "$LOG_FILE"
  else
    echo "$(date) - Chyba: svc.sh nenalezen v $AGENT_DIR před instalací služby" | sudo tee -a "$LOG_FILE"
    exit 1
  fi
done

# Úklid
sudo rm /tmp/agent.tar.gz 2>&1 | sudo tee -a "$LOG_FILE"
echo "$(date) - Script completed" | sudo tee -a "$LOG_FILE"
