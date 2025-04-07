#!/bin/bash

ROOT=$PWD

RED='\033[0;31m'
GREEN='\033[0;32m'
BRIGHT_GREEN='\033[1;92m'
PURPLE='\033[0;95m'
BLUE='\033[0;94m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_step() {
    echo -e "\n${CYAN}${BOLD}Step $1: $2${NC}"
}

check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Success!${NC}"
    else
        echo -e "${RED}✗ Failed! Please check errors above and try again.${NC}"
        exit 1
    fi
}

# Export environment variables
export PUB_MULTI_ADDRS
export PEER_MULTI_ADDRS
export HOST_MULTI_ADDRS
export IDENTITY_PATH
export ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120

# Set default values for environment variables if not already defined
DEFAULT_PUB_MULTI_ADDRS=""
PUB_MULTI_ADDRS=${PUB_MULTI_ADDRS:-$DEFAULT_PUB_MULTI_ADDRS}

DEFAULT_PEER_MULTI_ADDRS="/ip4/38.101.215.13/tcp/30002/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ"
PEER_MULTI_ADDRS=${PEER_MULTI_ADDRS:-$DEFAULT_PEER_MULTI_ADDRS}

DEFAULT_HOST_MULTI_ADDRS="/ip4/0.0.0.0/tcp/38331"
HOST_MULTI_ADDRS=${HOST_MULTI_ADDRS:-$DEFAULT_HOST_MULTI_ADDRS}

DEFAULT_IDENTITY_PATH="$ROOT"/swarm.pem
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

if [ -f "modal-login/temp-data/userData.json" ]; then
    cd modal-login
    source ~/.bashrc

    # Install npm if not present
    if ! command -v npm >/dev/null 2>&1; then
        echo -e "${YELLOW}npm is not installed. Installing Node.js and npm...${NC}"
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt-get install -y nodejs
        source ~/.bashrc
    fi

    echo -e "\n${CYAN}Installing dependencies with npm. This may take a few minutes, depending on your internet speed...${NC}"
    npm install --legacy-peer-deps

    # Start the development server in the background
    echo -e "\n${CYAN}Starting the development server...${NC}"
    npm run dev > server.log 2>&1 &
    SERVER_PID=$!
    MAX_WAIT=60
    counter=0
    while [ $counter -lt $MAX_WAIT ]; do
        if grep -q "Local:        http://localhost:" server.log; then
            PORT=$(grep "Local:        http://localhost:" server.log | sed -n 's/.*http:\/\/localhost:\([0-9]*\).*/\1/p')
            if [ -n "$PORT" ]; then
                echo -e "${GREEN}Server is running successfully on port $PORT\n${NC}"
                break
            fi
        fi
        sleep 1
        counter=$((counter + 1))
    done

    if [ $counter -eq $MAX_WAIT ]; then
        echo -e "${RED}Timeout waiting for server to start.${NC}"
        kill $SERVER_PID 2>/dev/null || true
        exit 1
    fi
    cd ..

    # Extract ORG_ID from userData.json
    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
    echo -e "${CYAN}ORG_ID has been set to: ${BOLD}$ORG_ID\n${NC}"

    # Cleanup function for graceful shutdown
    cleanup() {
        echo -e "${YELLOW}Shutting down server and ngrok...${NC}"
        kill $SERVER_PID 2>/dev/null || true
        exit 0
    }

    trap cleanup INT
    
else
    cd modal-login
    source ~/.bashrc
    if ! command -v npm >/dev/null 2>&1; then
        echo -e "${YELLOW}npm is not installed. Installing Node.js and npm...${NC}"
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt-get install -y nodejs
        source ~/.bashrc
    fi
    echo -e "\n${CYAN}Installing dependencies with npm. This may take a few minutes, depending on your internet speed...${NC}"
    npm install --legacy-peer-deps

    # Start the development server in the background
    echo -e "\n${CYAN}Starting the development server...${NC}"
    npm run dev > server.log 2>&1 &
    SERVER_PID=$!
    MAX_WAIT=60
    counter=0
    while [ $counter -lt $MAX_WAIT ]; do
        if grep -q "Local:        http://localhost:" server.log; then
            PORT=$(grep "Local:        http://localhost:" server.log | sed -n 's/.*http:\/\/localhost:\([0-9]*\).*/\1/p')
            if [ -n "$PORT" ]; then
                echo -e "${GREEN}Server is running successfully on port $PORT.${NC}"
                break
            fi
        fi
        sleep 1
        counter=$((counter + 1))
    done

    if [ $counter -eq $MAX_WAIT ]; then
        echo -e "${RED}Timeout waiting for server to start.${NC}"
        kill $SERVER_PID 2>/dev/null || true
        exit 1
    fi

    # Create a separate script file for ngrok to avoid blocking the main script
    cat <<EOF > run_ngrok.js
import ngrok from 'ngrok';
(async function() {
    try {
        const url = await ngrok.connect($PORT);
        console.log('\x1b[1;92m✓ Success! Please visit this website and log in using your email : \x1b[0m\x1b[0;94m' + url + '\x1b[0m');
    } catch (err) {
        console.error('\x1b[31mFailed to start ngrok:\x1b[0m', err);
        process.exit(1);
    }
})();
EOF

    # Launch ngrok tunnel in the background
    echo -e "\n${CYAN}Starting ngrok tunnel...${NC}"
    node run_ngrok.js &
    NGROK_PID=$!
    
    sleep 2 # Waiting 2 sec

    cd ..
    echo -e "\n${CYAN}Waiting for you to complete the login process...${NC}"
    while [ ! -f "modal-login/temp-data/userData.json" ]; do
        sleep 3
    done
    echo -e "${GREEN}${BOLD}✓ Success! The userData.json file has been created. Proceeding with remaining setups...${NC}"

    # Extract ORG_ID from userData.json
    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
    echo -e "\n${CYAN}ORG_ID has been set to: ${BOLD}$ORG_ID\n${NC}"

    # Cleanup function for graceful shutdown
    cleanup() {
        echo -e "${YELLOW}Shutting down server and ngrok processes...${NC}"
        kill $SERVER_PID 2>/dev/null || true
        kill $NGROK_PID 2>/dev/null || true
        pkill -f ngrok || true
        exit 0
    }

    trap cleanup INT
fi

# Install Python requirements
echo -e "${CYAN}Installing required Python packages...${NC}"
pip install -r "$ROOT"/requirements-hivemind.txt > /dev/null
pip install -r "$ROOT"/requirements.txt > /dev/null

# Determine config path based on hardware
if ! which nvidia-smi; then
    CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
elif [ -n "$CPU_ONLY" ]; then
    CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
else
    pip install -r "$ROOT"/requirements_gpu.txt > /dev/null
    CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
fi

echo -e "${GREEN}Awesome, All packages installed successfully!\n${NC}"

# Handle Hugging Face token
if [ -n "${HF_TOKEN}" ]; then
    HUGGINGFACE_ACCESS_TOKEN=${HF_TOKEN}
else
    read -p "Would you like to push models you train in the RL swarm to the Hugging Face Hub? [y/N] " yn
    yn=${yn:-N}
    case $yn in
        [Yy]* ) read -p "Enter your Hugging Face access token: " HUGGINGFACE_ACCESS_TOKEN;;
        [Nn]* ) HUGGINGFACE_ACCESS_TOKEN="None";;
        * ) echo -e "${YELLOW}>>> No answer was given, so NO models will be pushed to the Hugging Face Hub.${NC}" && HUGGINGFACE_ACCESS_TOKEN="None";;
    esac
fi

echo -e "\n${GREEN}${BOLD}Good luck in the swarm! Your training session is about to begin.\n${NC}"

# Run the Python training script with appropriate parameters
if [ -n "$ORG_ID" ]; then
    python -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --modal_org_id "$ORG_ID" \
        --config "$CONFIG_PATH"
else
    python -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --public_maddr "$PUB_MULTI_ADDRS" \
        --initial_peers "$PEER_MULTI_ADDRS" \
        --host_maddr "$HOST_MULTI_ADDRS" \
        --config "$CONFIG_PATH"
fi

wait
