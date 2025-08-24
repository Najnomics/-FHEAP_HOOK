import React, { useState, useEffect } from 'react';
import { BrowserRouter, Routes, Route, Link, useLocation } from 'react-router-dom';
import './App.css';
import axios from 'axios';

const BACKEND_URL = process.env.REACT_APP_BACKEND_URL;
const API = `${BACKEND_URL}/api`;

// ===== UTILITY COMPONENTS =====

const FHEValue = ({ encryptedValue, label, prefix = "$", decryptable = false }) => {
  const [isDecrypted, setIsDecrypted] = useState(false);
  const [decryptedValue, setDecryptedValue] = useState(null);

  const simulateDecrypt = (encrypted) => {
    try {
      const parts = encrypted.split('_');
      if (parts.length >= 3) {
        return (parseInt(parts[2]) / 1000000).toLocaleString('en-US', {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2
        });
      }
      return '••••••';
    } catch {
      return '••••••';
    }
  };

  const handleDecrypt = () => {
    if (!isDecrypted) {
      setDecryptedValue(simulateDecrypt(encryptedValue));
      setIsDecrypted(true);
    } else {
      setIsDecrypted(false);
      setDecryptedValue(null);
    }
  };

  return (
    <div className="fhe-value">
      <span className="fhe-label">{label}: </span>
      <span className="fhe-amount">
        {prefix}{isDecrypted && decryptedValue ? decryptedValue : '••••••'}
      </span>
      {decryptable && (
        <button 
          onClick={handleDecrypt}
          className="decrypt-btn"
          title={isDecrypted ? "Hide value" : "Decrypt with FHE permissions"}
        >
          {isDecrypted ? '🔓' : '🔒'}
        </button>
      )}
    </div>
  );
};

const StatusBadge = ({ status }) => {
  const getStatusColor = (status) => {
    switch (status) {
      case 'active': return 'bg-green-500';
      case 'triggered': return 'bg-yellow-500';
      case 'inactive': return 'bg-gray-500';
      case 'monitoring': return 'bg-blue-500';
      default: return 'bg-gray-500';
    }
  };

  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium text-white ${getStatusColor(status)}`}>
      {status.toUpperCase()}
    </span>
  );
};

// ===== DASHBOARD COMPONENT =====

const Dashboard = () => {
  const [dashboardData, setDashboardData] = useState(null);
  const [statistics, setStatistics] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchDashboardData = async () => {
      try {
        const [dashboardRes, statsRes] = await Promise.all([
          axios.get(`${API}/dashboard`),
          axios.get(`${API}/statistics`)
        ]);
        
        setDashboardData(dashboardRes.data);
        setStatistics(statsRes.data);
      } catch (error) {
        console.error('Error fetching dashboard data:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchDashboardData();
    const interval = setInterval(fetchDashboardData, 10000); // Update every 10 seconds
    return () => clearInterval(interval);
  }, []);

  if (loading) {
    return (
      <div className="flex justify-center items-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500"></div>
      </div>
    );
  }

  return (
    <div className="dashboard">
      {/* Header */}
      <div className="dashboard-header mb-8">
        <h1 className="text-4xl font-bold text-white mb-2">🛡️ FHEAP Dashboard</h1>
        <p className="text-gray-300">FHE Arbitrage Protection - Real-time MEV Defense</p>
      </div>

      {/* Key Metrics */}
      <div className="metrics-grid grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        <div className="metric-card">
          <div className="metric-value">
            <FHEValue 
              encryptedValue={dashboardData?.total_mev_captured || 'fhe_enc_0_0000'} 
              label="MEV Captured"
              decryptable={true}
            />
          </div>
          <div className="metric-change text-green-400">+12.5% (24h)</div>
        </div>

        <div className="metric-card">
          <div className="metric-value">
            <FHEValue 
              encryptedValue={dashboardData?.total_lp_rewards || 'fhe_enc_0_0000'} 
              label="LP Rewards"
              decryptable={true}
            />
          </div>
          <div className="metric-change text-green-400">+8.3% (24h)</div>
        </div>

        <div className="metric-card">
          <div className="metric-value text-2xl font-bold text-white">
            {dashboardData?.active_protections || 0}
          </div>
          <div className="metric-label">Active Protections</div>
          <div className="metric-change text-blue-400">Real-time</div>
        </div>

        <div className="metric-card">
          <div className="metric-value text-2xl font-bold text-white">
            {dashboardData?.protection_success_rate || 0}%
          </div>
          <div className="metric-label">Success Rate</div>
          <div className="metric-change text-green-400">+2.1% (24h)</div>
        </div>
      </div>

      {/* Protection Status */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
        <div className="protection-status-card">
          <h3 className="card-title">🎯 Protection Status</h3>
          <div className="protection-metrics">
            <div className="protection-metric">
              <span className="metric-label">Opportunities Detected (24h)</span>
              <span className="metric-value">{statistics?.arbitrage_opportunities_24h || 0}</span>
            </div>
            <div className="protection-metric">
              <span className="metric-label">Protections Triggered (24h)</span>
              <span className="metric-value">{statistics?.protections_triggered_24h || 0}</span>
            </div>
            <div className="protection-metric">
              <span className="metric-label">Avg Response Time</span>
              <span className="metric-value">{statistics?.average_protection_response_time_ms || 0}ms</span>
            </div>
          </div>
        </div>

        <div className="arbitrage-monitor-card">
          <h3 className="card-title">📊 Arbitrage Monitor</h3>
          <div className="monitor-status">
            <div className="status-indicator">
              <div className="status-dot animate-pulse bg-green-400"></div>
              <span>Cross-DEX Monitoring Active</span>
            </div>
            <div className="monitored-dexs">
              <div className="dex-badge">Uniswap V3</div>
              <div className="dex-badge">SushiSwap</div>
              <div className="dex-badge">Curve</div>
              <div className="dex-badge">Balancer</div>
            </div>
          </div>
        </div>
      </div>

      {/* Recent Events */}
      <div className="recent-events-card mb-8">
        <h3 className="card-title">⚡ Recent Protection Events</h3>
        <div className="events-list">
          {dashboardData?.recent_events?.slice(0, 5).map((event, index) => (
            <div key={event.id || index} className="event-item">
              <div className="event-time">
                {new Date(event.timestamp).toLocaleTimeString()}
              </div>
              <div className="event-details">
                <StatusBadge status={event.protection_status} />
                <FHEValue 
                  encryptedValue={event.encrypted_mev_captured} 
                  label="MEV Captured"
                  decryptable={true}
                />
              </div>
              <div className="event-tx">
                {event.tx_hash && (
                  <a 
                    href={`https://etherscan.io/tx/${event.tx_hash}`}
                    target="_blank" 
                    rel="noopener noreferrer"
                    className="tx-link"
                  >
                    View Tx
                  </a>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

// ===== ARBITRAGE MONITOR COMPONENT =====

const ArbitrageMonitor = () => {
  const [opportunities, setOpportunities] = useState([]);
  const [prices, setPrices] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchData = async () => {
      try {
        const [oppRes, pricesRes] = await Promise.all([
          axios.get(`${API}/arbitrage-opportunities?limit=20`),
          axios.get(`${API}/prices?limit=30`)
        ]);
        
        setOpportunities(oppRes.data);
        setPrices(pricesRes.data);
      } catch (error) {
        console.error('Error fetching arbitrage data:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchData();
    const interval = setInterval(fetchData, 5000); // Update every 5 seconds
    return () => clearInterval(interval);
  }, []);

  if (loading) {
    return (
      <div className="flex justify-center items-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500"></div>
      </div>
    );
  }

  return (
    <div className="arbitrage-monitor">
      <div className="monitor-header mb-8">
        <h1 className="text-4xl font-bold text-white mb-2">📊 Arbitrage Monitor</h1>
        <p className="text-gray-300">Real-time Cross-DEX Arbitrage Detection</p>
      </div>

      {/* Price Feed */}
      <div className="price-feed-card mb-8">
        <h3 className="card-title">💱 Live Price Feeds</h3>
        <div className="price-grid">
          {prices.slice(0, 6).map((price, index) => (
            <div key={price.id || index} className="price-item">
              <div className="price-header">
                <span className="token-pair">{price.token_pair}</span>
                <span className="dex-name">{price.dex_name}</span>
              </div>
              <div className="price-value">
                <FHEValue 
                  encryptedValue={price.encrypted_price} 
                  label=""
                  prefix="$"
                  decryptable={true}
                />
              </div>
              <div className="price-time">
                {new Date(price.timestamp).toLocaleTimeString()}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Arbitrage Opportunities */}
      <div className="opportunities-card">
        <h3 className="card-title">🎯 Detected Opportunities</h3>
        <div className="opportunities-list">
          {opportunities.map((opp, index) => (
            <div key={opp.id || index} className="opportunity-item">
              <div className="opp-header">
                <span className="token-pair">{opp.token_pair}</span>
                <span className="dex-pair">{opp.dex_a} ↔ {opp.dex_b}</span>
                {opp.protection_triggered && (
                  <StatusBadge status="triggered" />
                )}
              </div>
              <div className="opp-details">
                <FHEValue 
                  encryptedValue={opp.encrypted_spread} 
                  label="Spread"
                  decryptable={true}
                />
                <div className="opp-time">
                  {new Date(opp.timestamp).toLocaleTimeString()}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

// ===== LP REWARDS COMPONENT =====

const LPRewards = () => {
  const [rewards, setRewards] = useState([]);
  const [lpAddress, setLpAddress] = useState('0x742d35cc7bf6c8a2d7c69b2d4c8e2f3d4e5a91d2');
  const [loading, setLoading] = useState(false);
  const [totalRewards, setTotalRewards] = useState('fhe_enc_0_0000');

  const fetchRewards = async () => {
    if (!lpAddress) return;
    
    setLoading(true);
    try {
      const response = await axios.get(`${API}/lp-rewards/${lpAddress}`);
      setRewards(response.data);
      
      // Calculate total rewards (simulated)
      if (response.data.length > 0) {
        const total = response.data.length * 1250.75; // Simulate total
        setTotalRewards(`fhe_enc_${Math.floor(total * 1000000)}_1234`);
      }
    } catch (error) {
      console.error('Error fetching LP rewards:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchRewards();
  }, []);

  return (
    <div className="lp-rewards">
      <div className="rewards-header mb-8">
        <h1 className="text-4xl font-bold text-white mb-2">💰 LP Rewards</h1>
        <p className="text-gray-300">Your encrypted rewards from MEV protection</p>
      </div>

      {/* Address Input */}
      <div className="address-input-card mb-8">
        <h3 className="card-title">🔍 Check LP Address</h3>
        <div className="input-group">
          <input
            type="text"
            value={lpAddress}
            onChange={(e) => setLpAddress(e.target.value)}
            placeholder="0x... LP Address"
            className="address-input"
          />
          <button onClick={fetchRewards} className="check-btn">
            Check Rewards
          </button>
        </div>
      </div>

      {/* Total Rewards */}
      <div className="total-rewards-card mb-8">
        <h3 className="card-title">💎 Total Encrypted Rewards</h3>
        <div className="total-amount">
          <FHEValue 
            encryptedValue={totalRewards} 
            label="Total Claimable"
            decryptable={true}
          />
        </div>
        <button className="claim-btn">
          🔒 Claim with FHE Permissions
        </button>
      </div>

      {/* Rewards History */}
      <div className="rewards-history-card">
        <h3 className="card-title">📋 Rewards History</h3>
        {loading ? (
          <div className="text-center py-8">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500 mx-auto"></div>
          </div>
        ) : (
          <div className="rewards-list">
            {rewards.length === 0 ? (
              <div className="no-rewards">No rewards found for this address</div>
            ) : (
              rewards.map((reward, index) => (
                <div key={reward.id || index} className="reward-item">
                  <div className="reward-details">
                    <FHEValue 
                      encryptedValue={reward.encrypted_reward_amount} 
                      label="Amount"
                      decryptable={true}
                    />
                    <div className="reward-pool">Pool: {reward.pool_id}</div>
                  </div>
                  <div className="reward-status">
                    <StatusBadge status={reward.claimed ? 'claimed' : 'active'} />
                    <div className="reward-time">
                      {new Date(reward.timestamp).toLocaleDateString()}
                    </div>
                  </div>
                </div>
              ))
            )}
          </div>
        )}
      </div>
    </div>
  );
};

// ===== PROTECTION EVENTS COMPONENT =====

const ProtectionEvents = () => {
  const [events, setEvents] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchEvents = async () => {
      try {
        const response = await axios.get(`${API}/protection-events?limit=50`);
        setEvents(response.data);
      } catch (error) {
        console.error('Error fetching protection events:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchEvents();
    const interval = setInterval(fetchEvents, 15000); // Update every 15 seconds
    return () => clearInterval(interval);
  }, []);

  if (loading) {
    return (
      <div className="flex justify-center items-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500"></div>
      </div>
    );
  }

  return (
    <div className="protection-events">
      <div className="events-header mb-8">
        <h1 className="text-4xl font-bold text-white mb-2">⚡ Protection Events</h1>
        <p className="text-gray-300">Complete history of arbitrage protection activations</p>
      </div>

      <div className="events-list-card">
        <div className="events-grid">
          {events.map((event, index) => (
            <div key={event.id || index} className="event-card">
              <div className="event-header">
                <StatusBadge status={event.protection_status} />
                <div className="event-time">
                  {new Date(event.timestamp).toLocaleString()}
                </div>
              </div>
              
              <div className="event-metrics">
                <FHEValue 
                  encryptedValue={event.encrypted_protection_fee} 
                  label="Protection Fee"
                  decryptable={true}
                />
                <FHEValue 
                  encryptedValue={event.encrypted_mev_captured} 
                  label="MEV Captured"
                  decryptable={true}
                />
              </div>
              
              <div className="event-footer">
                <div className="gas-used">
                  Gas: {event.gas_used?.toLocaleString() || 'N/A'}
                </div>
                {event.tx_hash && (
                  <a 
                    href={`https://etherscan.io/tx/${event.tx_hash}`}
                    target="_blank" 
                    rel="noopener noreferrer"
                    className="tx-link"
                  >
                    View Transaction
                  </a>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

// ===== NAVIGATION COMPONENT =====

const Navigation = () => {
  const location = useLocation();

  const navItems = [
    { path: '/', label: 'Dashboard', icon: '🛡️' },
    { path: '/monitor', label: 'Monitor', icon: '📊' },
    { path: '/rewards', label: 'LP Rewards', icon: '💰' },
    { path: '/events', label: 'Events', icon: '⚡' },
  ];

  return (
    <nav className="navigation">
      <div className="nav-brand">
        <span className="brand-icon">🛡️</span>
        <span className="brand-text">FHEAP</span>
      </div>
      <div className="nav-links">
        {navItems.map((item) => (
          <Link
            key={item.path}
            to={item.path}
            className={`nav-link ${location.pathname === item.path ? 'active' : ''}`}
          >
            <span className="nav-icon">{item.icon}</span>
            <span className="nav-label">{item.label}</span>
          </Link>
        ))}
      </div>
    </nav>
  );
};

// ===== MAIN APP COMPONENT =====

const App = () => {
  return (
    <div className="App">
      <BrowserRouter>
        <div className="app-layout">
          <Navigation />
          <main className="main-content">
            <Routes>
              <Route path="/" element={<Dashboard />} />
              <Route path="/monitor" element={<ArbitrageMonitor />} />
              <Route path="/rewards" element={<LPRewards />} />
              <Route path="/events" element={<ProtectionEvents />} />
            </Routes>
          </main>
        </div>
      </BrowserRouter>
    </div>
  );
};

export default App;