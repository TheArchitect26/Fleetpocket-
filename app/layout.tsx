import type { Metadata } from 'next';
import './globals.css';
export const metadata:Metadata={title:'Fleet Pocket · MCY Control Tower',description:'The connected workspace for fleet operations. Musa Connect Yield.'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en"><body>{children}</body></html>;}
