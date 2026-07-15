# Первый практический маршрут: от создания проекта до деплоя и тестов

## 1. Создать проект

Самый простой старт — инициализировать новый Anchor-проект:

```bash
anchor init hello-world
cd hello-world
```

После этого у вас появятся каталог программы, тесты и файл `Anchor.toml` для настройки кластера. Anchor официально рекомендует именно такой стартовый сценарий.

## 2. Написать первый контракт

Откройте `programs/hello-world/src/lib.rs` и замените содержимое на минимальный пример:

```rust
use anchor_lang::prelude::*;

declare_id!("Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS");

#[program]
pub mod hello_world {
    use super::*;

    pub fn hello_world(_ctx: Context<HelloWorld>) -> Result<()> {
        msg!("Hello world, from Solana smart contract");
        Ok(())
    }
}

#[derive(Accounts)]
pub struct HelloWorld {}
```

Это базовая структура Anchor-программы: подключение `prelude`, объявление `program id`, модуль с инструкцией и пустая структура `Accounts`, если аккаунты пока не нужны.

Если хочется чуть полезнее, вместо `hello world` можно сделать **счётчик**: одна инструкция `initialize`, вторая `increment`, а в аккаунте хранить `count: u64`. Такой пример лучше показывает работу с состоянием.

## 3. Собрать программу

После изменения кода запустите сборку:

```bash
anchor build
```

Эта команда компилирует Rust-программу и создаёт артефакты в `target/deploy`. В официальных примерах Anchor это первый обязательный шаг перед деплоем.

## 4. Подготовить program id

После первой сборки Anchor сгенерирует ключ программы. Его нужно посмотреть и вставить в `declare_id!`, чтобы бинарник и on-chain program id совпадали.

```bash
anchor keys list
```

Дальше обновите строку:

```rust
declare_id!("ВАШ_PROGRAM_ID");
```

После этого **обязательно** снова выполните:

```bash
anchor build
```

Это важный шаг: новый program id должен быть встроен в бинарник до деплоя.

## 5. Настроить сеть для деплоя

Для учебного проекта обычно используют `devnet` или `localnet`. В `Anchor.toml` выставьте нужный кластер. Для devnet это выглядит так:

```toml
[provider]
cluster = "devnet"
wallet = "~/.config/solana/id.json"
```

Если вы тестируете локально, можно оставить `localnet` и использовать `solana-test-validator`. Anchor в своей документации отдельно показывает оба сценария: локальная сеть и devnet.

## 6. Задеплоить контракт

Перед деплоем убедитесь, что у вас есть SOL для комиссии и что кошелёк выбран правильно. Затем выполните:

```bash
anchor deploy
```

Если всё настроено верно, программа будет загружена в выбранный кластер. В примерах Anchor для devnet это именно следующий шаг после повторной сборки с правильным `declare_id!`.

## 7. Написать тест

Для Anchor-проекта тест обычно лежит в `tests/hello-world.ts`. Минимальный пример для вызова инструкции:

```ts
import * as anchor from "@coral-xyz/anchor";

describe("hello-world", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const program = anchor.workspace.HelloWorld as anchor.Program;

  it("calls hello_world", async () => {
    const tx = await program.methods.helloWorld().rpc();
    console.log("transaction:", tx);
  });
});
```

Более подробные инструкции по тестированию находятся в [HOWTOTEST.md](./docs/HOWTOTEST.md)

## 8. Запустить тесты

Более подробные инструкции по тестированию находятся в [HOWTOTEST.md](./docs/HOWTOTEST.md)

## 9. Проверить результат

После успешного теста студент должен увидеть три признака:

- `anchor build` проходит без ошибок.
- `anchor deploy` завершается успешно.
- `anchor test` выполняется и вызывает вашу инструкцию.

Для дополнительной проверки можно посмотреть состояние сети:

```bash
solana config get
solana address
solana balance
```

Если вы используете devnet, это поможет убедиться, что тесты идут не в пустоту и кошелёк реально подключён к нужной сети.

## 10. Что делать дальше

После первого `hello world` лучший следующий шаг — сделать программу с **состоянием**, например, vault/escrow. Так станут понятны три главные вещи: как описывать аккаунты, как писать инструкции и как проверять бизнес-логику тестами.

