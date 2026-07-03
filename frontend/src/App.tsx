import { useState } from "react";
import { Masthead } from "./components/Masthead";
import { VerifyTab } from "./components/VerifyTab";
import { IssuerTab } from "./components/IssuerTab";
import { WalletTab } from "./components/WalletTab";

const tabs = [
  { key: "verify", label: "Verify", note: "anyone, no wallet needed" },
  { key: "issuer", label: "Issuer desk", note: "register · issue · revoke" },
  { key: "wallet", label: "My credentials", note: "holder view" },
] as const;

type TabKey = (typeof tabs)[number]["key"];

export default function App() {
  const [active, setActive] = useState<TabKey>("verify");

  return (
    <div className="page">
      <Masthead />
      <nav className="ledger-tabs" aria-label="Sections">
        {tabs.map((tab) => (
          <button
            key={tab.key}
            className={active === tab.key ? "on" : ""}
            aria-current={active === tab.key ? "page" : undefined}
            onClick={() => setActive(tab.key)}
          >
            <span>{tab.label}</span>
            <span className="eyebrow">{tab.note}</span>
          </button>
        ))}
      </nav>
      <main>
        {active === "verify" && <VerifyTab />}
        {active === "issuer" && <IssuerTab />}
        {active === "wallet" && <WalletTab />}
      </main>
      <footer className="colophon">
        <span className="eyebrow">every claim on this page is checkable on-chain · built with foundry, wagmi and viem</span>
      </footer>
    </div>
  );
}
