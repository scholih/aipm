**Aan:** Marcel (CTO), Frans (CEO)
**Van:** Hans
**Onderwerp:** GenAI werkplekken Reflex BV — opzet klaar voor review

---

Hoi Marcel, Frans,

Ik heb een opzet gemaakt voor het inrichten van GenAI-werkplekken bij Reflex BV. Het idee: elke rol krijgt een eigen configuratie met de juiste tools, zodat iedereen er direct mee aan de slag kan — van developer tot helpdesk tot jullie als CTO/CEO.

**Wat zit erin:**

- **8 persona's** volledig uitgewerkt: Tech Subject Expert, Solution Architect, Developer, Tester, Helpdesk, Marketing, CEO en CTO
- **Per persona:** een Claude Code configuratie (CLAUDE.md), rol-beschrijving, en een op maat gemaakte sidecar (Python hulpscripts die lokaal draaien voor snelheid en kostenbesparing)
- **Gedeelde kennisbank:** hybride opzet met Obsidian (gratis, lokaal, AI-doorzoekbaar) + SharePoint (wat jullie al hebben). Nul extra licentiekosten.
- **Ollama** voor lokale AI — draait volledig op de laptop, data verlaat de machine niet. Gratis.
- **Automatische installer:** PowerShell script dat per persona alles in één keer opzet

**Wat het kost:**
- Ollama: gratis
- Obsidian: gratis
- Alle plugins: gratis/open source
- Enige kosten: Claude API tokens voor de complexere taken (PRD generatie, strategische analyses). Dagelijks gebruik via Ollama is gratis.

**Belangrijke disclaimer:**
Dit is een eerste opzet. Ik heb geen Windows machine, dus alles is **ongetest op Windows**. Het is gebouwd op basis van documentatie en best practices, maar het moet door iemand met een Windows laptop gevalideerd worden voordat het uitgerold wordt. Marcel, dit zou een mooie eerste taak zijn voor een developer in het team.

**Repo:** Ik heb alles in een publieke GitHub repo gezet zodat jullie developers er direct mee aan de slag kunnen. Link volgt zodra het live staat.

**Volgende stappen:**
1. **Voor dinsdag:** Bekijk de repo alvast zodat jullie een beeld hebben van de opzet. Aanstaande dinsdag ontmoet ik Alex (de developer) voor het eerst — het zou goed zijn als hij de repo ook al heeft bekeken, zodat we direct inhoudelijk kunnen doorpakken.
2. Marcel: laat Alex de installer testen op een Windows 11 laptop als eerste actie
3. Kijk samen of de persona-indelingen kloppen — past het bij hoe jullie werken?
4. Kies een pilot-groep (bijv. 2-3 mensen) om mee te starten
5. Na validatie: uitrol naar de rest van het team

**Repo:** https://github.com/scholih/aipm — het staat publiek zodat iedereen er direct bij kan.

Vragen of feedback? Laat het weten. Ik help graag mee bij het finetunen.

Groet,
Hans
