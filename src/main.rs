use std::{cell::Cell, net::SocketAddr, rc::Rc, time::Duration};

use anyhow::Result;
use clap::Parser;
use tokio::{
    net::{lookup_host, UdpSocket},
    task, time,
};
use tracing::{debug, info, trace, warn, Level};

const DNS_LOOKUP_RETRY_TIME: Duration = Duration::from_secs(10);
const DNS_LOOKUP_INTERVAL: Duration = Duration::from_secs(120);
const BUF_SIZE: usize = 2048;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// UDP listen port
    #[arg(short, long)]
    port: u16,
    /// Remote address, e.g. example.com:443
    #[arg(short, long)]
    remote: String,
    /// Log level: error/warn/info/debug/trace
    #[arg(short, long, default_value = "info")]
    log_level: Level,
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let args = Args::parse();
    tracing_subscriber::fmt()
        .with_max_level(args.log_level)
        .init();

    info!("Listen on {}; forward to {}", args.port, args.remote);
    let udp = UdpSocket::bind(("::", args.port)).await?;
    let remote: Rc<Cell<Option<SocketAddr>>> = Default::default();
    let local = task::LocalSet::new();

    // DNS lookup task
    let remote_ = remote.clone();
    local.spawn_local(async move {
        loop {
            let addr = match lookup_host(&args.remote).await.map(|mut a| a.next()) {
                Ok(Some(addr)) => addr,
                Ok(None) => {
                    warn!("No associated address for host {}", args.remote);
                    time::sleep(DNS_LOOKUP_INTERVAL).await;
                    continue;
                }
                Err(err) => {
                    warn!("Couldn't resolve host {}: {}", args.remote, err);
                    time::sleep(DNS_LOOKUP_RETRY_TIME).await;
                    continue;
                }
            };
            if remote_.get() != Some(addr) {
                info!("Resolved {} to {}", args.remote, addr);
                remote_.replace(Some(addr));
            }
            time::sleep(DNS_LOOKUP_INTERVAL).await;
        }
    });

    // UDP forwarding task
    local.spawn_local(async move {
        let mut local_addr: Option<SocketAddr> = None;
        let mut buf = [0u8; BUF_SIZE];
        loop {
            let (len, peer) = udp
                .recv_from(&mut buf)
                .await
                .expect("Error on read UDP socket");
            trace!("Received {} bytes packet from {}", len, peer);
            if peer.ip().is_loopback() {
                // Forward to remote
                if local_addr != Some(peer) {
                    local_addr = Some(peer);
                    info!("Set local address to {}", peer);
                }
                if let Some(remote) = remote.get() {
                    trace!("Forward {} bytes packet to {}", len, remote);
                    if let Err(err) = udp.send_to(&buf[..len], remote).await {
                        info!("I/O error on forwarding packet to remote: {}", err);
                    }
                } else {
                    debug!("Packet dropped: remote address not ready");
                }
            } else {
                // Forward to local
                if let Some(local) = local_addr {
                    trace!("Forward {} bytes packet to {}", len, local);
                    if let Err(err) = udp.send_to(&buf[..len], local).await {
                        info!("I/O error on forwarding packet to local: {}", err);
                    }
                } else {
                    debug!("Packet dropped: local address not ready");
                }
            }
        }
    });

    local.await;
    Ok(())
}
