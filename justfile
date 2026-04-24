# Проверяем версии утилит
sol-env-ver:
    rustc --version && solana --version && anchor --version && surfpool --version && node --version && yarn --version

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
sol-acc-create:
    solana-keygen new -o ~/.config/solana/id.json

# Проверяем баланс. В localhost на адресе уже есть 5 млн SOL для тестов
sol-get-bal:
    solana address; solana balance

# Получаем запас нативной валюты SOL при помощи айрдропа в devnet. Если получаем rate limit, идём браузером на faucet.solana.com, авторизуемся через GitHub и запрашиваем 2.5-5 SOL на наш счёт
sol-get-sol:
    solana airdrop 2

# Подписываемся на уведомления по транзакциям на кошельке друга
sol-acc-logs:
    solana logs H3S7NRkCqQtHbZztPY6FXKm264RSV1Vb6JWdPRaPa37s 

# Отправляем несколько SOL другу, наблюдаем за логами и проверяем балансы
sol-trans-sol:
    solana transfer H3S7NRkCqQtHbZztPY6FXKm264RSV1Vb6JWdPRaPa37s 0.5 --allow-unfunded-recipient

# Запускаем узел-валидатор локально (порт 8899)
sol-node-start:
    solana-test-validator

# Создаём новый токен
spl-tok-create:
    spl-token create-token

# Создаём аккаунт-держатель токенов
spl-tok-acc-create:
    spl-token create-account -p <program-id> <token> 

# Минтим токены на новом адресе
spl-tok-mint:
    spl-token mint <token> 678

# Отправляем несколько токенов тому же другу
spl-tok-trans:
    spl-token transfer <token> 400 H3S7NRkCqQtHbZztPY6FXKm264RSV1Vb6JWdPRaPa37s
