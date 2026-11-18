# Composants libres de Cadenza 0.4

Cette distribution embarque Pawnote LTS 1.6.4, la bibliothèque PRONOTE utilisée par Papillon, sous GPL-3.0-or-later. Le texte de licence est conservé dans ThirdParty/Pawnote-GPL-3.0.md. Le code Swift de cette version intégrée et ses modifications sont fournis dans ce dépôt et les archives de sources ; la distribution du travail combiné respecte les conditions GPL-3.0-or-later de Pawnote.

Le code correspondant du moteur embarqué est Runtime/src, avec package.json/package-lock.json, un patch Papillon épinglé et son applicateur vérifiant les empreintes avant et après transformation. Le bundle peut être reconstruit avec npm ci, npm test et npm run build dans Runtime. Aucune page distante ne fournit du code exécuté dans ce moteur.

Les sources amont complètes de Pawnote LTS 1.6.4 sont incluses dans [ThirdParty/Source/Pawnote-LTS-1.6.4-source.zip](ThirdParty/Source/Pawnote-LTS-1.6.4-source.zip). Le [manifeste de provenance](ThirdParty/Source/Pawnote-LTS-1.6.4-source.json) indique le commit amont et l’empreinte de cette archive. Les adaptations de Cadenza sont conservées dans Runtime/patches, Runtime/news-compatibility.mjs et Runtime/src.

Sources : https://github.com/BlocksHub/Pawnote-LTS et https://github.com/PapillonApp/Papillon/tree/93792b1fde14ad61a931ee4aab08321a0f42be2e/patches. Le design, les images et l’icône propres à Cadenza ne sont pas repris de Papillon.

Le raccourci HongMix Focus est réutilisé sous licence MIT, avec son nom et sa licence d’origine dans Resources/Shortcuts. Son fichier signé, son générateur source et son audience publique sont vérifiés par Scripts/verify_prebuilt_focus_shortcut.py ; les détails sont dans docs/CAPACITES_NATIVES.md.

Les licences des dépendances transitives du moteur sont incluses dans ThirdParty/Runtime-Licenses.txt. Les illustrations et références originales conservent leurs propres conditions lorsqu’elles en possèdent.
