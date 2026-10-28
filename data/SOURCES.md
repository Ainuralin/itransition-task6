# Lookup data

The CSV files contain static dictionaries. Selecting values, combining fields, formatting output and all runtime random-number generation happen exclusively in the SQL stored procedures.

## Python Faker 40.43.0 (MIT)

Chinese family and given names and Korean road stems were extracted from the static provider lists. The original frequency weights are not retained. The package is not a runtime dependency.

- https://github.com/joke2k/faker/tree/v40.43.0/faker/providers/person/zh_CN
- https://github.com/joke2k/faker/tree/v40.43.0/faker/providers/address/ko_KR
- License: FAKER_LICENSE.txt

## Faker JS 10.1.0 (MIT)

Korean family names and gender-grouped given names use these larger static lists. The generic given-name list is not separately sampled. Overlapping names can occur in both groups.

- https://github.com/faker-js/faker/tree/v10.1.0/src/locales/ko/person
- License: FAKER_JS_LICENSE.txt

## Other values

Chinese road names and city/district pairs are manually curated examples. Street, building and postcode combinations are fictional, not validated mailing addresses. Latin name forms are static ASCII transliterations prepared with Unidecode 1.4.0 and can differ from official personal romanization. Illustrative physical-distribution parameters are documented in docs/procedures.md; they are not empirical population statistics.
