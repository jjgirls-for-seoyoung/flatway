import { Outfit, Inter } from "next/font/google";
import "./globals.css";

const outfit = Outfit({
  subsets: ["latin"],
  variable: "--font-outfit",
  weight: ["300", "400", "500", "600", "700", "800"],
});

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
});

export const metadata = {
  title: "FlatWay - 보행 및 휠체어 안전 지도 대시보드",
  description: "실시간 단차 및 노면 파손 제보 정보를 기반으로 이동 약자에게 최적화된 우회 안전 경로를 안내합니다.",
};

export default function RootLayout({ children }) {
  return (
    <html lang="ko" className={`${outfit.variable} ${inter.variable}`}>
      <body>{children}</body>
    </html>
  );
}

