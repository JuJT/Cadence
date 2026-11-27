# Cadenza 0.9.0

Cadenza est un dérivé iPhone de [Papillon](https://github.com/PapillonApp/Papillon). Il reprend les écrans et parcours scolaires de Papillon avec l’icône et la palette bleu et blanc de Cadenza, ainsi que le suivi des révisions et du temps de travail.

- [Installer Cadenza sur iPhone](https://github.com/JuJT/Cadence/releases) et conserver le même compte de signature pour remplacer une installation Cadenza existante.
- Le code de cette version et sa méthode de construction sont fournis sous [GPL-3.0](LICENSE). La base est le commit [`3d983b338b8218286099db300f2cb4d61482c2e0`](https://github.com/PapillonApp/Papillon/commit/3d983b338b8218286099db300f2cb4d61482c2e0) de Papillon, avec les modifications recensées dans [la notice](THIRD_PARTY_NOTICES.md).
- Pour compiler la version iPhone, utiliser [le workflow iOS](.github/workflows/cadenza-ios.yml) ou les mêmes commandes Expo et Xcode sur macOS. La signature de l’IPA s’effectue avec le compte choisi pour l’installation.

Les trajets utilisent le catalogue du [Point d’accès national](https://transport.data.gouv.fr/) et les itinéraires et horaires [Transitous](https://transitous.org/sources/). La couverture et le temps réel dépendent des flux publiés par les réseaux. Les domiciles, leurs jours d’alternance et les photos de cartes restent dans l’app.

## Projet d’origine

<img width="1660" height="568" alt="Papillon" src="https://github.com/user-attachments/assets/7ed371b9-f196-4eba-a7e8-6c62991779f5" />

<p align="center"></p> <p align="center"> L'application libre et open source <b>ultime</b> pour gérer toute ta vie scolaire sans compromis. </p> <p align="center"> <a href="https://papillon.bzh/download"><picture><source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/58713fdf-1768-4093-9aba-cf09d01e296b"><source media="(prefers-color-scheme: light)" srcset="https://github.com/user-attachments/assets/5ce75010-f06f-446f-bee5-94745bf8ab15"><img alt="Télécharger" src="https://github.com/user-attachments/assets/5ce75010-f06f-446f-bee5-94745bf8ab15"></picture></a> <a href="https://papillon.bzh/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/43883003-54bd-4ad6-8660-4a23b1b6fe2b"><source media="(prefers-color-scheme: light)" srcset="https://github.com/user-attachments/assets/f435b124-3d2c-491d-9b59-e5b2ed90d024"><img alt="Site web" src="https://github.com/user-attachments/assets/f435b124-3d2c-491d-9b59-e5b2ed90d024"></picture></a> <a href="https://docs.papillon.bzh/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/fe722cf6-45e9-4cb4-a958-b7e21eb5cf0a"><source media="(prefers-color-scheme: light)" srcset="https://github.com/user-attachments/assets/2545f95a-d0e3-49e6-b628-0f16b009cf97"><img alt="Documentation" src="https://github.com/user-attachments/assets/2545f95a-d0e3-49e6-b628-0f16b009cf97"></picture></a> </p>

#

<h3 align="center"> 🦋 C'est quoi Papillon ? </h3> <p align="center"> Papillon est un client alternatif des services de vie scolaire conventionnels (Pronote, ÉcoleDirecte, Skolengo) ainsi que des services universitaires communs (Scodoc, Appscho, etc.). À l'aide de librairies externes, Papillon affiche les données de votre compte dans une interface moderne et intuitive. </p>

<p align="center">
<img width="272" height="381" alt="image" src="https://github.com/user-attachments/assets/482814d2-8263-4e1f-b20b-0675afe9fa06" />
<img width="272" height="381" alt="image" src="https://github.com/user-attachments/assets/f5eef7b4-3136-4f6b-9314-4f407ac9aca0" />
<img width="272" height="381" alt="image" src="https://github.com/user-attachments/assets/b58a8ab3-0214-4c8a-9abd-6ec4374efe9e" />
</p>

#

<h3 align="center"> 🛠️ Contribuer au projet </h3> <p align="center"> Si tu veux filer un coup de main, t'es au bon endroit ! Que tu sois dev, designer, traducteur·rice ou juste curieux·se, il y a de la place pour toi. </p> <p align="center"> <a href="https://docs.papillon.bzh/developper/compile"><img alt="Compiler" src="https://img.shields.io/badge/🧱_Compiler_l'app-2f6fed?style=for-the-badge"></a> <a href="https://docs.papillon.bzh/ui"><img alt="Papillon UI" src="https://img.shields.io/badge/🎨_Papillon_UI-8b5cf6?style=for-the-badge"></a> <a href="https://discord.gg/wVKWBRTbfh"><img alt="Discord" src="https://img.shields.io/badge/💬_Rejoindre_le_Discord-5865F2?style=for-the-badge"></a> </p>

#

<h3 align="center"> 👥 L'équipe </h3> <p align="center"> <a href="https://github.com/ecnivtwelve"><b>Vince</b></a> · <a href="https://github.com/tryon-dev"><b>Lucas</b></a> · <a href="https://github.com/godetremy"><b>Rémy</b></a> · <a href="https://github.com/tom-things"><b>Tom</b></a> · <a href="https://github.com/ryzenixx"><b>Mael</b></a> · <a href="https://github.com/raphckrman"><b>Raphaël</b></a> </p> <p align="center"> Et un énorme merci à <b>toutes les personnes qui contribuent</b> au projet 💚 </p> <p align="center"> <a href="https://github.com/PapillonApp/Papillon/graphs/contributors"> <img src="https://contrib.rocks/image?repo=PapillonApp/Papillon" alt="Contributeurs" /> </a> </p>

#

<h3 align="center"> ⭐ Un petit coup de pouce ? </h3> <p align="center"> Tu aimes Papillon ? Mets-nous une <b>étoile</b> sur GitHub (ça prend 2 secondes), parles-en à ta classe et à tes amis, ou viens nous dire bonjour sur le <a href="https://discord.gg/wVKWBRTbfh">Discord</a>. </p>

#

<h3 align="center"> 📜 Licence </h3> <p align="center"> Papillon est distribué sous licence <a href="./LICENSE"><b>GPL-3.0</b></a>. </p> <p align="center"> <sub>Fait avec 💚 (et beaucoup de café) en Bretagne (et plus loin encore)</sub> </p>
