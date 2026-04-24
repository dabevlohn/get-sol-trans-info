# Читаем настройки (~/.config/solana/cli/config.yml)
sol-conf-get:
    solana config get

# Работаем с Devnet (JSON RPC URL: https://api.devnet.solana.com)
sol-conf-dev:
    solana config set --url devnet

# Работаем с Localhost (JSON RPC URL: http://127.0.0.1:8899)
sol-conf-loc:
    solana config set --url localhost

# Создаём новый аккаунт
acc-create:
    solana-keygen new -o ~/.config/solana/id.json
