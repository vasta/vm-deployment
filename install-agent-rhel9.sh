#!/bin/bash
DEVOPS_URL=$1
PAT_TOKEN=$2
VM_NAME=$3
AGENT_COUNT=$4  
AGENT_POOL=$5
AGENT_USER="azagent"
BASE_DIR="/opt/devops-agents"  # Pevně daná cesta pro instalaci agentů
LOG_FILE="/var/log/install-agents.log"
API_VERSION="7.1"

echo "$(date) - Starting script" | sudo tee -a "$LOG_FILE"

# Vytvoření uživatele azagent, pokud ještě neexistuje
if ! id "$AGENT_USER" >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash "$AGENT_USER" 2>&1 | sudo tee -a "$LOG_FILE"
  echo "$(date) - Uživatel $AGENT_USER vytvořen" | sudo tee -a "$LOG_FILE"
else
  echo "$(date) - Uživatel $AGENT_USER již existuje" | sudo tee -a "$LOG_FILE"
fi

# Instalace závislostí pro RHEL 9 (nechávám zakomentované, pokud je potřeba, odkomentujte)
#sudo dnf update -y 2>&1 | sudo tee -a "$LOG_FILE"
#sudo dnf install -y curl unzip libicu 2>&1 | sudo tee -a "$LOG_FILE"

# Stažení agenta do dočasného adresáře
echo "$(date) - Stahování agenta" | sudo tee -a "$LOG_FILE"
curl -L https://vstsagentpackage.azureedge.net/agent/4.251.0/vsts-agent-linux-x64-4.251.0.tar.gz -o /tmp/agent.tar.gz 2>&1 | sudo tee -a "$LOG_FILE"
if [ $? -ne 0 ] || [ ! -f "/tmp/agent.tar.gz" ]; then
  echo "$(date) - Chyba: Stažení agenta selhalo nebo soubor nenalezen" | sudo tee -a "$LOG_FILE"
  exit 1
fi
echo "$(date) - Agent úspěšně stažen: $(ls -l /tmp/agent.tar.gz)" | sudo tee -a "$LOG_FILE"

# Zajistit, že soubor je čitelný
sudo chmod 644 /tmp/agent.tar.gz 2>&1 | sudo tee -a "$LOG_FILE"




# Čištění předchozí konfigurace
sudo rm -rf /etc/systemd/system/vsts.agent.vzp* 2>&1 | sudo tee -a "$LOG_FILE"
sudo rm -rf ${BASE_DIR}/ 2>&1 | sudo tee -a "$LOG_FILE"

# Získání POOL_ID podle názvu poolu
echo "Hledám POOL_ID pro pool s názvem: $AGENT_POOL..."
POOL_ID=$(curl -u :$PAT_TOKEN -s "$DEVOPS_URL/_apis/distributedtask/pools?api-version=$API_VERSION" | jq -r ".value[] | select(.name==\"$AGENT_POOL\") | .id")

# Kontrola, zda bylo nalezeno POOL_ID
if [[ -z "$POOL_ID" ]]; then
    echo "Chyba: Agent pool '$AGENT_POOL' neexistuje!"
fi

echo "Nalezeno POOL_ID: $POOL_ID"

# Získání seznamu agentů v daném poolu
echo "Získávám seznam agentů v poolu $AGENT_POOL..."
AGENTS=$(curl -u :$PAT_TOKEN -s "$DEVOPS_URL/_apis/distributedtask/pools/$POOL_ID/agents?api-version=$API_VERSION" | jq -r '.value[].id')


# Mazání všech agentů v daném poolu
if [[ -n "$AGENTS" ]]; then
    echo "Mažu všechny agenty v poolu '$AGENT_POOL'..."
    for AGENT_ID in $AGENTS; do
        echo "Mazání agenta ID: $AGENT_ID..."
        curl -u :$PAT_TOKEN -X DELETE -s "$DEVOPS_URL/_apis/distributedtask/pools/$POOL_ID/agents/$AGENT_ID?api-version=$API_VERSION"
        echo "Agent ID $AGENT_ID byl smazán."
    done
else
    echo "Pool '$AGENT_POOL' neobsahuje žádné agenty. Není co mazat."
fi






# Instalace a konfigurace více agentů
for i in $(seq 1 $AGENT_COUNT); do
  AGENT_NAME="${VM_NAME}-agent-0${i}"
  AGENT_DIR="${BASE_DIR}/myagent0${i}"

  echo "$(date) - Instalace agenta $AGENT_NAME do $AGENT_DIR" | sudo tee -a "$LOG_FILE"

  # Vytvoření adresáře a nastavení vlastníka na azagent
  sudo mkdir -p "$AGENT_DIR" 2>&1 | sudo tee -a "$LOG_FILE"
  sudo chown -R azagent:azagent "$AGENT_DIR" 2>&1 | sudo tee -a "$LOG_FILE"
  echo "$(date) - Adresář $AGENT_DIR vytvořen: $(ls -ld $AGENT_DIR)" | sudo tee -a "$LOG_FILE"

  # Kopie agenta
  echo "$(date) - Kopírování agenta do $AGENT_DIR" | sudo tee -a "$LOG_FILE"
  sudo cp /tmp/agent.tar.gz "$AGENT_DIR" 2>&1 | sudo tee -a "$LOG_FILE"
  if [ $? -ne 0 ] || [ ! -f "$AGENT_DIR/agent.tar.gz" ]; then
    echo "$(date) - Chyba: agent.tar.gz nebyl zkopírován do $AGENT_DIR" | sudo tee -a "$LOG_FILE"
    echo "$(date) - Oprávnění /tmp/agent.tar.gz: $(ls -l /tmp/agent.tar.gz)" | sudo tee -a "$LOG_FILE"
    echo "$(date) - Oprávnění $AGENT_DIR: $(ls -ld $AGENT_DIR)" | sudo tee -a "$LOG_FILE"
    exit 1
  fi
  echo "$(date) - Agent úspěšně zkopírován: $(ls -l $AGENT_DIR/agent.tar.gz)" | sudo tee -a "$LOG_FILE"

  # Vyčištění adresáře před rozbalením (kromě agent.tar.gz)
  echo "$(date) - Čištění $AGENT_DIR před rozbalením" | sudo tee -a "$LOG_FILE"
  sudo find "$AGENT_DIR" -type f ! -name 'agent.tar.gz' -delete 2>&1 | sudo tee -a "$LOG_FILE"
  sudo find "$AGENT_DIR" -type d ! -path "$AGENT_DIR" -delete 2>&1 | sudo tee -a "$LOG_FILE"

  # Rozbalení agenta
  echo "$(date) - Rozbalování agenta v $AGENT_DIR" | sudo tee -a "$LOG_FILE"
  sudo -u $AGENT_USER bash -c "cd $AGENT_DIR && tar -xzf $AGENT_DIR/agent.tar.gz" 2>&1 | sudo tee -a "$LOG_FILE"
  echo "$(date) - Obsah $AGENT_DIR po rozbalení: $(ls -l $AGENT_DIR)" | sudo tee -a "$LOG_FILE"

  # Konfigurace agenta pod uživatelem azagent
  echo "$(date) - Konfigurace agenta v $AGENT_NAME" | sudo tee -a "$LOG_FILE"
  sudo -u $AGENT_USER bash -c "cd $AGENT_DIR && ./config.sh --unattended \
    --url '$DEVOPS_URL' \
    --auth pat \
    --token '$PAT_TOKEN' \
    --pool '$AGENT_POOL' \
    --agent '$AGENT_NAME' \
    --acceptTeeEula" 2>&1 | sudo tee -a "$LOG_FILE"
  if [ $? -ne 0 ]; then
    echo "$(date) - Chyba: Konfigurace agenta $AGENT_NAME selhala" | sudo tee -a "$LOG_FILE"
    exit 1
  fi

  # Instalace a spuštění služby pod uživatelem azagent
  echo "$(date) - Instalace a spuštění agenta $AGENT_NAME" | sudo tee -a "$LOG_FILE"
  sudo bash -c "cd $AGENT_DIR && ./svc.sh install $AGENT_USER" 2>&1 | sudo tee -a "$LOG_FILE"
  sudo bash -c "cd $AGENT_DIR && ./svc.sh start" 2>&1 | sudo tee -a "$LOG_FILE"
done

# Úklid
sudo rm /tmp/agent.tar.gz 2>&1 | sudo tee -a "$LOG_FILE"
echo "$(date) - Script completed" | sudo tee -a "$LOG_FILE"
