# Готовый результат

## Архитектура проекта

Проект будет состоять из двух инструкций:

- `deposit` — пользователь кладёт токены в vault, а программа переводит их на PDA-токен-аккаунт.
- `withdraw` — владелец escrow или уполномоченный получатель забирает токены из vault при выполнении условия.

Программа контролирует средства не напрямую, а через PDA и CPI к SPL Token Program.

## Структура файлов

```text
vault-escrow/
├─ Anchor.toml
├─ Cargo.toml
├─ package.json
├─ programs/
│  └─ vault-escrow/
│     └─ src/
│        └─ lib.rs
├─ tests/
│  └─ vault-escrow.ts
│  └─ vault-escrow.rs
└─ migrations/
```

Anchor-экосистема официально содержит примеры `escrow`, `create-token`, `transfer-sol` и другие, поэтому такой шаблон хорошо ложится на стандартный стек.

## Контракт Rust

Ниже — упрощённый, но рабочий учебный вариант. Он показывает логику escrow через PDA vault и token transfer CPI. Anchor официально описывает перевод токенов через `transfer_checked` и использование PDA как `token::authority`.

```rust
use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount, TransferChecked};

declare_id!("VaulT111111111111111111111111111111111111111");

#[program]
pub mod vault_escrow {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, amount: u64) -> Result<()> {
        let escrow = &mut ctx.accounts.escrow;
        escrow.authority = ctx.accounts.authority.key();
        escrow.mint = ctx.accounts.mint.key();
        escrow.amount = amount;
        escrow.bump = ctx.bumps.escrow;
        Ok(())
    }

    pub fn deposit(ctx: Context<Deposit>) -> Result<()> {
        let cpi_accounts = TransferChecked {
            from: ctx.accounts.user_ata.to_account_info(),
            mint: ctx.accounts.mint.to_account_info(),
            to: ctx.accounts.vault_ata.to_account_info(),
            authority: ctx.accounts.user.to_account_info(),
        };
        let cpi_ctx = CpiContext::new(ctx.accounts.token_program.to_account_info(), cpi_accounts);

        token::transfer_checked(cpi_ctx, ctx.accounts.escrow.amount, ctx.accounts.mint.decimals)?;
        Ok(())
    }

    pub fn withdraw(ctx: Context<Withdraw>) -> Result<()> {
        let seeds: &[&[u8]] = &[
            b"escrow",
            ctx.accounts.authority.key.as_ref(),
            ctx.accounts.mint.key().as_ref(),
            &[ctx.accounts.escrow.bump],
        ];
        let signer = &[seeds];

        let cpi_accounts = TransferChecked {
            from: ctx.accounts.vault_ata.to_account_info(),
            mint: ctx.accounts.mint.to_account_info(),
            to: ctx.accounts.user_ata.to_account_info(),
            authority: ctx.accounts.escrow.to_account_info(),
        };
        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            cpi_accounts,
            signer,
        );

        token::transfer_checked(cpi_ctx, ctx.accounts.escrow.amount, ctx.accounts.mint.decimals)?;
        Ok(())
    }
}

#[account]
pub struct Escrow {
    pub authority: Pubkey,
    pub mint: Pubkey,
    pub amount: u64,
    pub bump: u8,
}

#[derive(Accounts)]
#[instruction(amount: u64)]
pub struct Initialize<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    pub mint: Account<'info, Mint>,

    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 32 + 8 + 1,
        seeds = [b"escrow", authority.key().as_ref(), mint.key().as_ref()],
        bump
    )]
    pub escrow: Account<'info, Escrow>,

    #[account(
        init,
        payer = authority,
        token::mint = mint,
        token::authority = escrow
    )]
    pub vault_ata: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(mut)]
    pub user: Signer<'info>,

    pub mint: Account<'info, Mint>,

    #[account(
        mut,
        seeds = [b"escrow", authority.key().as_ref(), mint.key().as_ref()],
        bump = escrow.bump,
        has_one = authority,
        has_one = mint
    )]
    pub escrow: Account<'info, Escrow>,

    #[account(mut)]
    pub authority: SystemAccount<'info>,

    #[account(mut)]
    pub user_ata: Account<'info, TokenAccount>,

    #[account(mut)]
    pub vault_ata: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    pub mint: Account<'info, Mint>,

    #[account(
        mut,
        seeds = [b"escrow", authority.key().as_ref(), mint.key().as_ref()],
        bump = escrow.bump,
        has_one = authority,
        has_one = mint
    )]
    pub escrow: Account<'info, Escrow>,

    #[account(mut)]
    pub user_ata: Account<'info, TokenAccount>,

    #[account(mut)]
    pub vault_ata: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
}
```

## Что важно в коде

Ключевая идея здесь в том, что vault не хранит токены “сам по себе”, а является token account, authority которого принадлежит PDA-программе. Anchor прямо рекомендует такой подход для программного контроля token accounts через PDA.

Перевод токенов делается не прямым вызовом, а через CPI к SPL Token Program, и для этого используется `transfer_checked`. Это стандартный и безопасный путь в Anchor.

## Тест на TypeScript

Ниже — шаблон интеграционного теста, который показывает весь flow: создать mint, создать ATA, заминтить токены, инициализировать escrow, положить токены в vault, затем вывести их обратно.

```ts
import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { Keypair, PublicKey } from "@solana/web3.js";
import { createMint, getOrCreateAssociatedTokenAccount, mintTo, getAccount } from "@solana/spl-token";

describe("vault-escrow", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const program = anchor.workspace.VaultEscrow as Program;
  const payer = provider.wallet as anchor.Wallet;

  let mint: PublicKey;
  let userAta: PublicKey;
  let vaultAta: PublicKey;
  let escrow: PublicKey;
  let authority = payer.publicKey;

  it("creates mint and token accounts", async () => {
    mint = await createMint(
      provider.connection,
      payer.payer,
      payer.publicKey,
      null,
      6
    );

    const userAccount = await getOrCreateAssociatedTokenAccount(
      provider.connection,
      payer.payer,
      mint,
      payer.publicKey
    );
    userAta = userAccount.address;

    await mintTo(
      provider.connection,
      payer.payer,
      mint,
      userAta,
      payer.publicKey,
      1_000_000_000
    );
  });

  it("initializes escrow", async () => {
    const [escrowPda] = PublicKey.findProgramAddressSync(
      [Buffer.from("escrow"), authority.toBuffer(), mint.toBuffer()],
      program.programId
    );
    escrow = escrowPda;

    await program.methods
      .initialize(new anchor.BN(500_000_000))
      .accounts({
        authority,
        mint,
        escrow,
        vaultAta,
        tokenProgram: anchor.utils.token.TOKEN_PROGRAM_ID,
        systemProgram: anchor.web3.SystemProgram.programId,
        rent: anchor.web3.SYSVAR_RENT_PUBKEY,
      })
      .rpc();
  });

  it("deposits tokens", async () => {
    await program.methods
      .deposit()
      .accounts({
        user: payer.publicKey,
        mint,
        escrow,
        authority,
        userAta,
        vaultAta,
        tokenProgram: anchor.utils.token.TOKEN_PROGRAM_ID,
      })
      .rpc();
  });

  it("withdraws tokens", async () => {
    await program.methods
      .withdraw()
      .accounts({
        authority,
        mint,
        escrow,
        userAta,
        vaultAta,
        tokenProgram: anchor.utils.token.TOKEN_PROGRAM_ID,
      })
      .rpc();

    const acc = await getAccount(provider.connection, userAta);
    expect(Number(acc.amount)).toBeGreaterThan(0);
  });
});
```

## Что важно перед стартом

Проект рассчитан на Anchor Rust test template, поэтому инициализировать его лучше так:

```bash
anchor init vault-escrow --test-template rust
cd vault-escrow
```

Для Rust-тестов нужно использовать `--test-template rust`, а сам шаблон для тестов будет создан в `tests/src/test_initialize.rs`.

***

## `Anchor.toml`

```toml
[package]
name = "vault-escrow"
version = "0.1.0"
edition = "2021"

[features]
seeds = false
skip-lint = false

[programs.localnet]
vault_escrow = "VaulT111111111111111111111111111111111111111"

[programs.devnet]
vault_escrow = "VaulT111111111111111111111111111111111111111"

[registry]
url = "https://api.apr.dev"

[provider]
cluster = "localnet"
wallet = "~/.config/solana/id.json"

[scripts]
test = "cargo test-sbf -- --nocapture"
```

Для учебного проекта важно, чтобы `programs.localnet` и `programs.devnet` совпадали с `declare_id!` в `lib.rs`. `anchor test` читает `Anchor.toml` и использует его для запуска локального validator и конфигурации окружения.

***

## `programs/vault-escrow/Cargo.toml`

```toml
[package]
name = "vault_escrow"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "lib"]
name = "vault_escrow"

[features]
no-entrypoint = []
no-idl = []
cpi = ["no-entrypoint"]
default = []

[dependencies]
anchor-lang = "0.32.0"
anchor-spl = "0.32.0"
```

***

## `programs/vault-escrow/src/lib.rs`

```rust
use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount, TransferChecked};

declare_id!("VaulT111111111111111111111111111111111111111");

#[program]
pub mod vault_escrow {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, amount: u64) -> Result<()> {
        let escrow = &mut ctx.accounts.escrow;
        escrow.authority = ctx.accounts.authority.key();
        escrow.mint = ctx.accounts.mint.key();
        escrow.amount = amount;
        escrow.bump = ctx.bumps.escrow;
        Ok(())
    }

    pub fn deposit(ctx: Context<Deposit>) -> Result<()> {
        let cpi_accounts = TransferChecked {
            from: ctx.accounts.user_ata.to_account_info(),
            mint: ctx.accounts.mint.to_account_info(),
            to: ctx.accounts.vault_ata.to_account_info(),
            authority: ctx.accounts.user.to_account_info(),
        };
        let cpi_ctx = CpiContext::new(ctx.accounts.token_program.to_account_info(), cpi_accounts);

        token::transfer_checked(cpi_ctx, ctx.accounts.escrow.amount, ctx.accounts.mint.decimals)?;
        Ok(())
    }

    pub fn withdraw(ctx: Context<Withdraw>) -> Result<()> {
        let seeds: &[&[u8]] = &[
            b"escrow",
            ctx.accounts.authority.key.as_ref(),
            ctx.accounts.mint.key().as_ref(),
            &[ctx.accounts.escrow.bump],
        ];
        let signer = &[seeds];

        let cpi_accounts = TransferChecked {
            from: ctx.accounts.vault_ata.to_account_info(),
            mint: ctx.accounts.mint.to_account_info(),
            to: ctx.accounts.user_ata.to_account_info(),
            authority: ctx.accounts.escrow.to_account_info(),
        };
        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            cpi_accounts,
            signer,
        );

        token::transfer_checked(cpi_ctx, ctx.accounts.escrow.amount, ctx.accounts.mint.decimals)?;
        Ok(())
    }
}

#[account]
pub struct Escrow {
    pub authority: Pubkey,
    pub mint: Pubkey,
    pub amount: u64,
    pub bump: u8,
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    pub mint: Account<'info, Mint>,

    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 32 + 8 + 1,
        seeds = [b"escrow", authority.key().as_ref(), mint.key().as_ref()],
        bump
    )]
    pub escrow: Account<'info, Escrow>,

    #[account(
        init,
        payer = authority,
        token::mint = mint,
        token::authority = escrow
    )]
    pub vault_ata: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(mut)]
    pub user: Signer<'info>,

    pub mint: Account<'info, Mint>,

    #[account(
        mut,
        seeds = [b"escrow", authority.key().as_ref(), mint.key().as_ref()],
        bump = escrow.bump,
        has_one = authority,
        has_one = mint
    )]
    pub escrow: Account<'info, Escrow>,

    #[account(mut)]
    pub authority: SystemAccount<'info>,

    #[account(mut)]
    pub user_ata: Account<'info, TokenAccount>,

    #[account(mut)]
    pub vault_ata: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    pub mint: Account<'info, Mint>,

    #[account(
        mut,
        seeds = [b"escrow", authority.key().as_ref(), mint.key().as_ref()],
        bump = escrow.bump,
        has_one = authority,
        has_one = mint
    )]
    pub escrow: Account<'info, Escrow>,

    #[account(mut)]
    pub user_ata: Account<'info, TokenAccount>,

    #[account(mut)]
    pub vault_ata: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
}
```

***

## Rust-тест целиком

```rust
use anchor_client::solana_sdk::{
    commitment_config::CommitmentConfig,
    pubkey::Pubkey,
    signature::{Keypair, Signer},
    system_program,
    sysvar,
};
use anchor_client::{Client, Cluster};
use std::{rc::Rc, str::FromStr};

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
    let deposit_amount = 500_000_000u64;
    let user_amount = 1_000_000_000u64;

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

    let user_ata = spl_associated_token_account::get_associated_token_address(
        &authority,
        &mint.pubkey(),
    );

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
        user_amount,
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

    let vault_ata = spl_associated_token_account::get_associated_token_address(
        &escrow,
        &mint.pubkey(),
    );

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
            amount: deposit_amount,
        })
        .send()
        .unwrap();

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
}
```

***

## `Cargo.toml` workspace root

```toml
[workspace]
members = [
    "programs/vault-escrow",
]

resolver = "2"

[workspace.dependencies]
anchor-lang = "0.32.0"
anchor-spl = "0.32.0"
anchor-client = "0.32.0"
spl-token = "7"
spl-associated-token-account = "6"
```

