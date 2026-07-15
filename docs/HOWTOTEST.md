# Тестирование на Rust

Для `vault/escrow` на Rust лучше сделать **отдельный Rust test template** при инициализации проекта, а затем запускать `anchor test` с localnet. Нужно использовать `--test-template rust`. Тесты по умолчанию выполняются на `localnet` и при необходимости автоматически поднимают локальный валидатор; если он уже запущен вручную, используют `--skip-local-validator`.

## Команды инициализации

Если проект ещё не создан, правильный старт такой:

```bash
anchor init vault-escrow --test-template rust
cd vault-escrow
```

Если проект уже создан с TypeScript-тестами, но следует на Rust, то практичнее создать новый workspace с Rust-template, чем вручную переделывать весь scaffolding.

## Как устроены Rust-тесты

При `--test-template rust` тестовый файл Anchor будет лежать в `tests/src/test_initialize.rs`. Anchor documentation указывает, что Rust-тесты выполняются через встроенный Rust client, а не через TypeScript runner.

Для escrow-проекта логика тестов должна быть такой:

1. Создать mint.
2. Создать token accounts для пользователя.
3. Сминтить токены пользователю.
4. Инициализировать escrow.
5. Выполнить `deposit`.
6. Выполнить `withdraw`.
7. Проверить балансы и состояние аккаунтов.

## Пример Rust-теста

Ниже — **Rust-версия** теста для escrow. Она ориентирована на обычный Anchor Rust client, который и рекомендуется для `--test-template rust`.

```rust
use anchor_lang::prelude::*;
use anchor_client::solana_sdk::{
    commitment_config::CommitmentConfig,
    signature::{Keypair, Signer},
    system_program,
};
use anchor_client::{Client, Cluster};
use std::rc::Rc;
use spl_associated_token_account::get_associated_token_address;
use spl_token::instruction as token_instruction;

#[test]
fn test_vault_escrow() {
    let payer = Keypair::new();
    let program_id = Pubkey::from_str("VaulT111111111111111111111111111111111111111").unwrap();

    let url = Cluster::Localnet;
    let client = Client::new_with_options(url, Rc::new(payer), CommitmentConfig::processed());
    let program = client.program(program_id);

    let mint = Keypair::new();

    let authority = program.payer();

    let user_ata = get_associated_token_address(&authority, &mint.pubkey());

    let (escrow_pda, _bump) = Pubkey::find_program_address(
        &[b"escrow", authority.as_ref(), mint.pubkey().as_ref()],
        &program_id,
    );

    let vault_ata = get_associated_token_address(&escrow_pda, &mint.pubkey());

    let decimals = 6u8;
    let deposit_amount = 500_000_000u64;

    let _ = program
        .request()
        .instruction(system_program::create_account(
            &program.payer(),
            &mint.pubkey(),
            1_000_000_000,
            spl_token::state::Mint::LEN as u64,
            &spl_token::id(),
        ))
        .instruction(
            token_instruction::initialize_mint(
                &spl_token::id(),
                &mint.pubkey(),
                &authority,
                None,
                decimals,
            )
            .unwrap(),
        )
        .signer(&mint)
        .send()
        .unwrap();

    let _ = program
        .request()
        .instruction(
            spl_associated_token_account::instruction::create_associated_token_account(
                &program.payer(),
                &authority,
                &mint.pubkey(),
                &spl_token::id(),
            ),
        )
        .send()
        .unwrap();

    let _ = program
        .request()
        .instruction(
            token_instruction::mint_to(
                &spl_token::id(),
                &mint.pubkey(),
                &user_ata,
                &authority,
                &[],
                1_000_000_000,
            )
            .unwrap(),
        )
        .send()
        .unwrap();

    let _ = program
        .request()
        .accounts(vault_escrow::accounts::Initialize {
            authority,
            mint: mint.pubkey(),
            escrow: escrow_pda,
            vault_ata,
            token_program: spl_token::id(),
            system_program: system_program::id(),
            rent: sysvar::rent::id(),
        })
        .args(vault_escrow::instruction::Initialize {
            amount: deposit_amount,
        })
        .send()
        .unwrap();

    let _ = program
        .request()
        .accounts(vault_escrow::accounts::Deposit {
            user: authority,
            mint: mint.pubkey(),
            escrow: escrow_pda,
            authority,
            user_ata,
            vault_ata,
            token_program: spl_token::id(),
        })
        .args(vault_escrow::instruction::Deposit {})
        .send()
        .unwrap();

    let _ = program
        .request()
        .accounts(vault_escrow::accounts::Withdraw {
            authority,
            mint: mint.pubkey(),
            escrow: escrow_pda,
            user_ata,
            vault_ata,
            token_program: spl_token::id(),
        })
        .args(vault_escrow::instruction::Withdraw {})
        .send()
        .unwrap();
}
```

Этот пример показывает идею, но для реального учебного проекта следует использовать уже сгенерированный Anchor Rust client и сверить имена модулей инструкций с тем, что сгенерирует ваш workspace, потому что они зависят от названия программы и структуры `lib.rs`.

## Как запускать тесты

Если локальный валидатор не запущен вручную:

```bash
anchor test
```

На `localnet` Anchor автоматически поднимет validator, соберёт и задеплоит программу, выполнит тесты и потом остановит validator. Это стандартный путь для Rust и TypeScript шаблонов.

Можно запустить локальный validator отдельно, тогда:

```bash
solana-test-validator
```

в одном терминале, а в другом:

```bash
anchor test --skip-local-validator
```

Флаг `--skip-local-validator` нужен, чтобы Anchor не пытался стартовать второй валидатор поверх уже работающего.

Лучше избегать запуска конкретного тестового сценария через `cargo test`, это уже не основной путь Anchor integration tests; для полноценного escrow-сценария предпочтительнее `anchor test`, потому что он учитывает сборку, деплой и конфигурацию кластера.

## Что проверить после запуска

После успешного прогона должны выполняться три вещи: `anchor build` проходит без ошибок, `anchor test` завершает сценарий, а в логах видно, что инструкции `initialize`, `deposit` и `withdraw` вызываются в нужном порядке.

Для проверки балансов можно добавить в тест чтение token account через SPL Token state и сделать `assert_eq!` по ожидаемым суммам. Это особенно полезно для escrow, потому что именно балансы подтверждают корректность логики.

## Рекомендуемый учебный вариант

```bash
anchor init vault-escrow --test-template rust
cd vault-escrow
anchor build
anchor test
```

Если validator уже запущен отдельно:

```bash
solana-test-validator
anchor test --skip-local-validator
```

Для учебного `vault/escrow` тест должен показывать **изменение балансов до и после**, а не просто успешный `rpc()` вызов. Ниже — Rust-тест, который явно печатает и проверяет balances user ATA и vault ATA через десериализацию SPL token account. Anchor рекомендует Rust test template, а для чтения/проверки состояний аккаунтов удобно использовать Rust client и SPL Token account data.

## Что должен проверять тест

1. Баланс `user_ata` до `deposit`.
2. Баланс `vault_ata` до `deposit`.
3. Баланс `user_ata` и `vault_ata` после `deposit`.
4. Баланс `user_ata` и `vault_ata` после `withdraw`.
5. Данные `Escrow`-аккаунта: `authority`, `mint`, `amount`, `bump`.

## Rust test file

Файл: `tests/src/test_initialize.rs`

```rust
use anchor_client::solana_sdk::{
    commitment_config::CommitmentConfig,
    pubkey::Pubkey,
    signature::{Keypair, Signer},
    system_program,
    sysvar,
};
use anchor_client::{Client, Cluster};
use spl_associated_token_account::get_associated_token_address;
use spl_token::state::Account as SplTokenAccount;
use std::{rc::Rc, str::FromStr};

fn token_amount(program: &anchor_client::Program, account: Pubkey) -> u64 {
    let data = program.rpc().get_account_data(&account).unwrap();
    let token_account = SplTokenAccount::unpack(&data).unwrap();
    token_account.amount
}

#[test]
fn test_vault_escrow_flow() {
    let payer = Keypair::new();
    let client = Client::new_with_options(
        Cluster::Localnet,
        Rc::new(payer),
        CommitmentConfig::processed(),
    );

    let program_id = Pubkey::from_str("VaulT111111111111111111111111111111111111111").unwrap();
    let program = client.program(program_id);

    let authority = program.payer();
    program.rpc().request_airdrop(&authority, 5_000_000_000).unwrap();

    let mint = Keypair::new();
    let decimals = 6u8;
    let escrow_amount = 500_000_000u64;
    let user_mint_amount = 1_000_000_000u64;

    let mint_rent = program
        .rpc()
        .get_minimum_balance_for_rent_exemption(spl_token::state::Mint::LEN)
        .unwrap();

    let create_mint_ix = system_program::create_account(
        &authority,
        &mint.pubkey(),
        mint_rent,
        spl_token::state::Mint::LEN as u64,
        &spl_token::id(),
    );

    let init_mint_ix = spl_token::instruction::initialize_mint(
        &spl_token::id(),
        &mint.pubkey(),
        &authority,
        Some(&authority),
        decimals,
    )
    .unwrap();

    program
        .request()
        .instruction(create_mint_ix)
        .instruction(init_mint_ix)
        .signer(&mint)
        .send()
        .unwrap();

    let user_ata = get_associated_token_address(&authority, &mint.pubkey());

    let create_user_ata_ix =
        spl_associated_token_account::instruction::create_associated_token_account(
            &authority,
            &authority,
            &mint.pubkey(),
            &spl_token::id(),
        );

    program
        .request()
        .instruction(create_user_ata_ix)
        .send()
        .unwrap();

    let mint_to_ix = spl_token::instruction::mint_to(
        &spl_token::id(),
        &mint.pubkey(),
        &user_ata,
        &authority,
        &[],
        user_mint_amount,
    )
    .unwrap();

    program
        .request()
        .instruction(mint_to_ix)
        .send()
        .unwrap();

    let (escrow, _escrow_bump) = Pubkey::find_program_address(
        &[b"escrow", authority.as_ref(), mint.pubkey().as_ref()],
        &program_id,
    );

    let vault_ata = get_associated_token_address(&escrow, &mint.pubkey());

    program
        .request()
        .accounts(vault_escrow::accounts::Initialize {
            authority,
            mint: mint.pubkey(),
            escrow,
            vault_ata,
            token_program: spl_token::id(),
            system_program: system_program::ID,
            rent: sysvar::rent::ID,
        })
        .args(vault_escrow::instruction::Initialize {
            amount: escrow_amount,
        })
        .send()
        .unwrap();

    let escrow_data = program.account::<vault_escrow::Escrow>(escrow).unwrap();
    assert_eq!(escrow_data.authority, authority);
    assert_eq!(escrow_data.mint, mint.pubkey());
    assert_eq!(escrow_data.amount, escrow_amount);

    let user_before = token_amount(&program, user_ata);
    let vault_before = token_amount(&program, vault_ata);
    assert_eq!(user_before, user_mint_amount);
    assert_eq!(vault_before, 0);

    program
        .request()
        .accounts(vault_escrow::accounts::Deposit {
            user: authority,
            mint: mint.pubkey(),
            escrow,
            authority,
            user_ata,
            vault_ata,
            token_program: spl_token::id(),
        })
        .args(vault_escrow::instruction::Deposit {})
        .send()
        .unwrap();

    let user_after_deposit = token_amount(&program, user_ata);
    let vault_after_deposit = token_amount(&program, vault_ata);
    assert_eq!(user_after_deposit, user_mint_amount - escrow_amount);
    assert_eq!(vault_after_deposit, escrow_amount);

    program
        .request()
        .accounts(vault_escrow::accounts::Withdraw {
            authority,
            mint: mint.pubkey(),
            escrow,
            user_ata,
            vault_ata,
            token_program: spl_token::id(),
        })
        .args(vault_escrow::instruction::Withdraw {})
        .send()
        .unwrap();

    let user_after_withdraw = token_amount(&program, user_ata);
    let vault_after_withdraw = token_amount(&program, vault_ata);
    assert_eq!(user_after_withdraw, user_mint_amount);
    assert_eq!(vault_after_withdraw, 0);
}
```

## Что будет при запуске

При успешном прогоне можно увидеть не только `test passed`, но и то, что все `assert_eq!` прошли: user ATA теряет токены на `deposit`, vault ATA получает их, а после `withdraw` баланс возвращается обратно. Это именно тот результат, который подтверждает корректную работу escrow-логики.

## Как самому просмотреть балансы

Для ручной проверки в терминале полезны команды:

```bash
spl-token accounts --owner <WALLET_PUBKEY>
spl-token balance <MINT_ADDRESS>
solana account <TOKEN_ACCOUNT_ADDRESS>
```

Эти команды показывают, какие token accounts существуют и какие у них балансы, что удобно для сверки с логикой теста.

## Что можно менять

Для escrow/vault самый понятный вариант — поменять **сумму перевода** в `initialize(amount)` или сделать её вычисляемой из входных данных. Тогда после деплоя тест сразу начнёт ожидать другие балансы.

Ещё хорошие варианты:

- изменить размер `escrow_amount`;
- добавить комиссию, например `fee_bps`;
- запретить withdraw, пока не выполнено условие;
- поменять получателя `withdraw`;
- добавить `cancel`, чтобы средства возвращались обратно автору escrow.


## Самый наглядный эксперимент

Самый простой учебный эксперимент — в `initialize` сохранить не `500_000_000`, а, например, `250_000_000`. Тогда после `deposit` тест должен увидеть:

- `user_ata` уменьшился на `250_000_000`;
- `vault_ata` увеличился на `250_000_000`;
- после `withdraw` токены вернулись обратно.

## Что именно править в коде

В нашем проекте можно сделать такие изменения в `lib.rs`:

```rust
pub fn initialize(ctx: Context<Initialize>, amount: u64) -> Result<()> {
    let escrow = &mut ctx.accounts.escrow;
    escrow.amount = amount;
    Ok(())
}
```

А затем запустить проект с другим значением:

```rust
.args(vault_escrow::instruction::Initialize {
    amount: 250_000_000,
})
```

После этого в тестах нужно обновить ожидания:

```rust
assert_eq!(user_after_deposit, user_mint_amount - 250_000_000);
assert_eq!(vault_after_deposit, 250_000_000);
```

Это самый прямой способ увидеть, что изменение кода изменило результат.

## Если хочется сильнее заметить разницу

Можно сделать поведение ещё более очевидным:

- добавить комиссию, например `escrow_amount + fee`;
- округлять сумму вверх или вниз;
- разрешать withdraw только после отдельного флага `released = true`;
- менять mint или recipient в зависимости от параметра.

Тогда студент увидит не только изменение баланса, но и изменение ветки исполнения: одна и та же команда теста либо проходит, либо падает в зависимости от нового правила.

## Как проверять результат

Правильный цикл такой:

1. Изменить `lib.rs`.
2. Выполнить `anchor build`.
3. Выполнить `anchor deploy` или `anchor test`.
4. Сравнить фактические балансы с ожидаемыми в тесте.

Если программа изменилась, но тест всё ещё проходит без правок ожиданий, значит изменение было косметическим и не повлияло на бизнес-логику. Для учебной задачи это не очень полезно.

