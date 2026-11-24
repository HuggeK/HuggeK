## <img src="https://user-images.githubusercontent.com/48095810/130605912-97ae066b-ae88-4a48-824f-8fb13c3658e4.png" width="28" alt=""> veckonr

[veckonr](https://github.com/HuggeK/veckonr) is a Chromium extension that
shows the current ISO 8601 week number right in your browser toolbar.
Never wonder which week it is again. **Install it for free:**

[**Get it for Microsoft Edge**](https://microsoftedge.microsoft.com/addons/detail/veckonummer/bmoffkcljddjmejkgflbpfcchhjekahf) ·
[**Get it for Chrome**](https://chrome.google.com/webstore/detail/week-number/dgjiedcgmmfaolcgieilddloapakcfhh)

## Golf and OpenStreetMap

- [OpenFlight](https://github.com/open-flight/openflight): open-source golf
  launch monitor. I'm one of the project's maintainers.
- **Golf tagging in OSM:** I help improve how golf is mapped in
  OpenStreetMap. I'm one of the authors of the proposal
  [Relation:Sport for golf courses](https://wiki.openstreetmap.org/wiki/Proposal:Relation:Sport_for_golf_courses),
  which defines how to map facilities with more than one course, the tees
  each course is played from, and scorecard values that differ by tee. I also
  help with [FairwayMapper](https://www.fairwaymapper.com/), a tool that gets
  golfers mapping their own courses.
- [golfTiles](https://github.com/HuggeK/golfTiles): free, open-source vector
  tiles and a MapLibre GL style for golf courses, built from OpenStreetMap
  data. Most golf apps show plain raster OSM maps that can't display everything
  mapped on a course, so golfTiles defines a vector tile schema for zoom 14+
  and scripts (osmium + tilemaker) to generate your own PMTiles.
  [Demo](https://huggek.github.io/golfTiles/)
- [OpenYardage](https://openyardage.com/en/): create a yardage book with
  distances, hazards and elevation change hole by hole from OpenStreetMap, and
  print it for free. Please check it out, it's awesome! I've helped by
  proposing improvements and by recording LiDAR scans of greens with my phone
  to validate the green slope maps it generates from DEM sources with
  international coverage.

## Energy

I contribute to [FTW](https://ftw.sourceful.energy), a local-first home energy
management system (EMS):

- [srcfl/ftw](https://github.com/srcfl/ftw): the EMS itself, coordinating solar, batteries, grid and EV charging.

<details>
<summary>More FTW repositories</summary>

- [srcfl/device-drivers](https://github.com/srcfl/device-drivers): public source, contracts and tests for Sourceful device drivers.
- [srcfl/device-simulator](https://github.com/srcfl/device-simulator): simulator for inverters, batteries, EV chargers and energy meters over Modbus TCP, MQTT and OCPP.
- [srcfl/home-assistant-addons](https://github.com/srcfl/home-assistant-addons): Home Assistant add-ons for FTW.
- [srcfl/ftw-web](https://github.com/srcfl/ftw-web): the FTW website.

</details>

[negative-price-calc](https://github.com/srcfl/negative-price-calc) shows how
negative electricity prices affect your solar export. I improved it so it runs
entirely in the browser, meaning your file never leaves your computer, and
added more metrics to the results.

[emmaboda-gk-ocpi-dashboard](https://github.com/HuggeK/emmaboda-gk-ocpi-dashboard)
is a dashboard for my golf club's EV chargers. It reads every charging session
from the operator over OCPI and the grid meter's hourly values from E.ON, then
shows how much of each monthly power peak (effektavgift) the chargers caused,
what they earn and cost, and whether the charging price covers it. It is
published every hour by GitHub Actions, and has a plain-language guide in
Swedish for the club's members.
[See it live](https://huggek.github.io/emmaboda-gk-ocpi-dashboard/)
[Try it](https://huggek.github.io/negative-price-calc/)

## Tools

- [export-mermaid-to-svg-vs-code](https://github.com/HuggeK/export-mermaid-to-svg-vs-code):
  VS Code extension that exports Mermaid diagrams to SVG with one click, from
  `.mmd` files or every diagram in a Markdown file. It also fixes blank labels
  and missing shapes when the SVGs are opened in Word or Inkscape.

I sent fixes to [PINGMapper](https://github.com/CameronBodine/PINGMapper)
(side-scan sonar to benthic habitat maps),
[claude-from-here](https://github.com/NYBaywatch/claude-from-here) and
[buzz](https://github.com/block/buzz).

## Local projects

- [klattorp.se](https://klattorp.se/): digitised photo albums from the village
  of Klättorp in Vissefjärda, so the old pictures are kept and anyone in the
  village can browse them. With this project I focused on learning about EXIF
  metadata: each picture carries its own description in its metadata, which
  the website renders as the caption and which follows the picture when you
  download it. Built with Hugo. ([source](https://github.com/HuggeK/klattorp.se))
- [tornfvof.se](https://tornfvof.se): website of Törn och Törngöls
  fiskevårdsområdesförening (FVOF), which manages fishing in the lakes Törn and
  Törngöl in Emmaboda. It collects fishing permits, rules, maps of the water
  areas and old depth charts, plus an archive of the association's documents,
  statutes and court rulings. The interactive map loads MapLibre only
  when it scrolls into view and waits for a tap on Data Saver connections.
  ([source](https://github.com/HuggeK/tornfvofse))

  **For other fiskevårdsområdesföreningar:** the repository also contains the
  QGIS project behind the map, and step-by-step instructions (in Swedish) for
  [making your own vattenområdeskarta](https://github.com/HuggeK/tornfvofse/blob/main/metod_f%C3%B6r_att_skapa_vattenomr%C3%A5den.md)
  from Lantmäteriet's open property data.
- [beskattningFVOF](https://github.com/HuggeK/beskattningFVOF): a Jupyter
  notebook about taxation in a medlemsbeskattad rättsamfällighetsförening,
  such as a FiskeVårdsOmrådesFörening. The association isn't taxed itself: each member declares their
  andel of the yearly result, but only above Skatteverket's exception of
  1,500 kr (this year's amount, subject to change). Given every property's andel in a CSV file, the notebook simulates
  each possible result. It plots how many members must declare and the total
  they declare, and prints the breakpoints: the result to stay under before
  more members have to declare. Name, exception and range are set at the top
  of the notebook.

## Projects to do

- [hugge.se](https://github.com/HuggeK/hugge.se): my personal website, built
  with Hugo.
- [rikstelefon](https://github.com/HuggeK/rikstelefon): decode the rotary
  dial of a 1924 Ericsson BC 310 telephone with an ESP32-C6, using the ESP-IDF
  pulse counter (PCNT).
