use anyhow::Result;
use solana_client::{nonblocking::rpc_client::RpcClient, rpc_config::RpcTransactionConfig};
use solana_commitment_config::CommitmentConfig;
use solana_sdk::signature::Signature;
use solana_transaction_status_client_types::UiTransactionEncoding;
use std::str::FromStr;

#[tokio::main]
async fn main() -> Result<()> {
    let client = RpcClient::new_with_commitment(
        String::from("https://api.devnet.solana.com"),
        CommitmentConfig::confirmed(),
    );

    let tx_sig = Signature::from_str(
        "rP16Mcpo3vWdufRar7xFDiveFqA1tJcYVHuvGUVwHaNUm5q8yrNNs5dpjNmqAiBdtiQhPTZjj53LorNfiqsdcK5",
    )?;

    let config = RpcTransactionConfig {
        commitment: CommitmentConfig::finalized().into(),
        encoding: UiTransactionEncoding::Json.into(),
        max_supported_transaction_version: Some(0),
    };

    let transaction = client.get_transaction_with_config(&tx_sig, config).await?;

    println!("{:#?}", transaction);

    Ok(())
}
