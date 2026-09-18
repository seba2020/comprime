import type { Metadata } from "next";
import { Analytics } from "@vercel/analytics/next";
import "./globals.css";
export const metadata: Metadata = { title: "Comprime — Mismas fotos. Menos peso.", description: "Comprime carpetas completas de imágenes en tu Mac. Local, rápido y sin subir tus fotos." };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="es"><body>{children}<Analytics /></body></html>; }
