UPDATE resultats
SET nom = (ARRAY[
    'OUEDRAOGO Wendyam', 'SAWADOGO Fatoumata', 'KABORE Moussa', 'TRAORE Awa',
    'SANOGO Abdoulaye', 'BAMBARA Aminata', 'ZONGO Cheick', 'COMPAORE Salimata',
    'ILBOUDO Souleymane', 'DIALLO Nafissatou', 'KONE Barkwende', 'OUATTARA Pingdwende',
    'GANAME Kiswendsida', 'YAMEOGO Rayangnewende', 'SOME Alassane', 'NABALOUM Mariam',
    'TIENDREBEOGO Adama', 'BADINI Kadidiatou', 'KERE Oumarou', 'ROAMBA Ibrahim'
])[((SUBSTRING(matricule FROM 4)::integer - 1) % 20 + 1)::integer];
