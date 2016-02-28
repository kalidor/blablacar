Since there is no public API for intreract with your account on Blablacar, I did something to do so.

Here is what it works:
+ List planned trip with passengers (tel, note, age, etc.)
+ Respond to a public question
+ Enter trip validation code
+ Enter trip passenger opinion
+ Request money transfer
+ Check money transfer status
+ Get current user opinions
+ Duplicate passed or planned trip (Please use YYYY/MM/DD) (error are displayed but it works, still working on it)
+ Update number of seats for a trip (Please use YYYY/MM/DD)

List planned trip:
```bash
Lyon -> Annecy (Vendredi 18 Dec à 17:50). Trip seen 56 times
  |  [COMPLETE]
  |  Hugo K (21 ans) 4.4★ (XX XX XX XX XX) :: [1 seat(s)] - Lyon -> Annecy
  |  Amelie R (20 ans) 4.1★ (XX XX XX XX XX) :: [1 seat(s)] - Lyon -> Chambery
  |  Christophe R (27 ans) 4.5★ (XX XX XX XX XX) :: [1 seat(s)] - Lyon -> Annecy
```

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
  INN H (1 place - 9 €) - Annecy -> Lyon [Virement en cours]
  TNT A (1 place - 6 €) - Lyon -> Chambéry [Virement en cours]
  SYT C (1 place - 9 €) - Annecy -> Lyon [Virement en cours]
  SYH K (1 place - 9 €) - Annecy -> Lyon [Virement en cours]
  OAI E (2 places - 18 €) - Bron -> Annecy [Verifications en cours]
  FDN R (1 place - 9 €) - Lyon -> Annecy [Virement effectué le 04/12/2015]
  UOK S (2 places - 6 €) - Lyon -> Chambéry [Virement effectué le 04/12/2015]
```

Send an opinion about a passenger / driver:
```bash
[8:40 ~/bin/blabla:master]% ./blablacar.rb -p --user "Christophe R" --avis "Sympa, ponctuel. Des discussions vraiment interessantes\!\! Je recommande" --note 5
[+] Starting: 2015-10-15 08:41:12 +0200
[+] Authenticated!
Apres votre voyage Bron-Annecy, laissez un avis a votre passager Christophe R
Avis envoye
```
Multiple option in one command line:
```
[20:51 ~/Codes/blablacar]% ./blablacar.rb -lNMm
[+] Authenticated
No new messages  # -m
Notification:    # -N
Après votre voyage Lyon-Annecy, laissez un avis à votre passager Arthur D
Après votre voyage Lyon-Annecy, laissez un avis à votre passager Marie
Total already requested: 1 467 €  # -M
Available money: 69 €             # -M
Getting next planned trips:       # -l
No future planned trip(s)
```

Ask for transfert money:
```
[11:00 ~/Codes/blablacar]% ./blablacar.rb -t
[+] Authenticated
Transfer successfully requested
```

Update seat for a trip (set up 2 seats for this trip):
```
[11:00 ~/Codes/blablacar]% ./blablacar.rb -T "2015/12/14" -S 2
[+] Authenticated
OK
```

Duplicate trip:
```
[11:00 ~/Codes/blablacar]% ./blablacar.rb --duplicate "2015/12/12 à 6h" --trip "2015/12/14 à 6h"
[+] Authenticated
[+] Trip is being processed...
[+] Trip duplicated
```
