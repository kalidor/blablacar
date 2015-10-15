Since there is no public API for intreract with your account on Blablacar, I did something to do so.

Here is what it works:
+ list planned trip with passengers (tel, note, age, etc.)
+ respond to a public question
+ enter trip validation code
+ enter trip passenger opinion
+ request money transfer
+ check money transfer status
+ get current user opinions

Show notifications:
```bash
[8:19 ~/bin/blabla:master]% ./blablacar.rb -N
[+] Starting: 2015-10-15 08:19:43 +0200
[+] Authenticated!
Notifications:
Apres votre voyage Annecy-Bron, renseignez le code passager de Christel C pour recevoir €9 rapidement.
Apres votre voyage Bron-Annecy, renseignez le code passager de Rodolphe B pour recevoir €9 rapidement.
Apres votre voyage Bron-Annecy, renseignez le code passager de Christophe R pour recevoir €9 rapidement.
Apres votre voyage Bron-Annecy, laissez un avis a votre passager Frederic O
```

Register code to confirm we had a trip with "Christophe R":
```bash
[8:19 ~/bin/blabla:master]% ./blablacar.rb --user "Christophe R" --code GIRSXK
[+] Starting: 2015-10-15 08:20:03 +0200
[+] Authenticated!
Apres votre voyage Bron-Annecy, renseignez le code passager de Christophe R pour recevoir €9 rapidement.
[+] Code ok pour Christophe R
```

Show payment status:
```bash
[8:20 ~/bin/blabla:master]% ./blablacar.rb -s
Transfer successfully requested
Money status (lastpage):
  Mathilde L (2 places - 18 €) - Bron -> Annecy [Verifications en cours]
  Lucie B (1 place - 9 €) - Bron -> Annecy [Verifications en cours]
  Aurelien N (1 place - 9 €) - Bron -> Annecy [Verifications en cours]
  Audrey H (1 place - 9 €) - Bron -> Annecy [Processing transfer]
  Alexandre R (1 place - 9 €) - Annecy -> Bron [Processing transfer]
  Alice B (1 place - 9 €) - Bron -> Annecy [Verifications en cours]
  Bastien C (1 place - 9 €) - Annecy -> Bron [Verifications en cours]
  Samia M (1 place - 9 €) - Bron -> Annecy [Verifications en cours]
  Fabien A (3 places - 27 €) - Lyon -> Annecy [Virement en cours]
  Nathanael L (1 place - 9 €) - Bron -> Annecy [Verifications en cours]
```

Send an opinion about a passenger / driver:
```bash
[8:40 ~/bin/blabla:master]% ./blablacar.rb -p --user "Christophe R" --avis "Sympa, ponctuel. Des discussions vraiment interessantes\!\!" Je recommande --note 5
[+] Starting: 2015-10-15 08:41:12 +0200
[+] Authenticated!
Apres votre voyage Bron-Annecy, laissez un avis a votre passager Christophe R
Avis envoye
```
