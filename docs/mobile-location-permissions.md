# Localisation mobile et suivi des livreurs

## Comportement actuellement implémenté

- `DeviceLocationService.current()` vérifie que le service de localisation est activé, demande la permission au runtime si nécessaire et récupère une position précise.
- Dans l'espace livreur, le partage commence après une action explicite du livreur.
- Une première position est envoyée immédiatement, puis une nouvelle position est demandée toutes les 15 secondes tant que l'écran livreur reste actif.
- Les envois sont maintenant sérialisés : une nouvelle demande ne démarre pas si la précédente est encore en cours.
- Une erreur d'envoi périodique arrête le partage et affiche un message demandant au livreur de le réactiver. Les erreurs asynchrones du timer ne sont donc plus laissées sans gestion.
- La position est transmise au backend via le dépôt coursier ; les RPC et politiques serveur restent responsables de vérifier l'identité, le rôle et l'affectation active.

## Permissions natives observées

### Android

Le manifeste déclare :
- `INTERNET`;
- `ACCESS_FINE_LOCATION`;
- `ACCESS_COARSE_LOCATION`;
- `POST_NOTIFICATIONS`.

Il ne déclare pas `ACCESS_BACKGROUND_LOCATION` ni de service de premier plan de type localisation.

### iOS

`Info.plist` contient les descriptions d'usage de localisation au premier plan et « Always », ainsi que les modes d'arrière-plan `fetch` et `remote-notification`.

Il ne contient pas le mode d'arrière-plan `location`.

## Limite importante — pas de suivi garanti en arrière-plan

Le mécanisme Flutter actuel utilise un `Timer.periodic` lié à l'écran livreur. Il n'est pas un service de localisation en arrière-plan. Si l'application est suspendue, fermée, si le processus est arrêté ou si l'écran est quitté, les mises à jour toutes les 15 secondes ne sont pas garanties.

La présence d'une description iOS « Always » ne suffit pas à rendre le suivi actif en arrière-plan. De même, les permissions Android de localisation au premier plan ne constituent pas une implémentation de service de localisation en arrière-plan.

## Étape de production à prévoir

Pour activer le suivi en arrière-plan, concevoir et valider séparément :
1. un service natif/Flutter adapté à Android et iOS, avec gestion du cycle de vie et reprise après interruption ;
2. les permissions minimales et justifications propres à chaque plateforme ;
3. un indicateur visible et un consentement explicite du livreur pendant le suivi ;
4. l'arrêt automatique à la fin, à l'annulation ou à la révocation de l'affectation ;
5. une limitation de fréquence, de précision et de rétention pour réduire la consommation batterie et l'exposition des données de localisation ;
6. les tests sur appareils réels, y compris refus de permission, mode économie d'énergie, perte réseau, suspension et redémarrage.

Ne pas ajouter automatiquement les permissions « Always » ou arrière-plan avant que le service correspondant soit réellement implémenté et que les parcours de consentement soient prêts.
