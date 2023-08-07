-- new breweries in Sydney in 2020

create or replace view Q1(brewery,suburb)
as
	Select Br.name, Lo.town

	From 
	Locations Lo, Breweries Br

	Where 
	Lo.metro = 'Sydney' and
	Br.located_in = Lo.id and
	Br.founded = '2020'
;

-- beers whose name is same as their style

create or replace view Q2(beer,brewery)
as
	Select Be.name, Br.name

	From
	Beers Be, Breweries Br, Styles St, Brewed_by BB, Contains Co

	Where
	St.name = Be.name and
	Br.id = BB.brewery and
	Be.style = St.id and 
	Be.id = BB.beer
	
;


-- original Californian craft brewery

create or replace view Q3(brewery,founded)
as
	Select Br.name, Br.founded
	
	From 
	Breweries Br, Locations Lo

	Where
	Lo.region = 'California' and
	Br.located_in = Lo.id and
	Br.founded <= All(
						Select BrTemp.founded

						From
						Breweries BrTemp, Locations LoTemp

						Where
						LoTemp.region = 'California' and
						BrTemp.located_in = LoTemp.id
					)
;

-- all IPA variations, and how many times each occurs

create or replace view Q4(style,count)
as
	Select St.name, count(Be.name)

	From
	Styles St, Beers Be

	Where
	St.name ~ 'IPA' and
	St.id = Be.style

	Group By
	St.name
;

-- all Californian breweries, showing precise location

create or replace view Q5 (brewery,location)
as
	Select Br.name, Coalesce(Lo.town, Lo.metro)

	From
	Locations Lo, Breweries Br

	Where
	Lo.region = 'California' and
	Br.located_in = Lo.id
	
;


-- strongest barrel-aged beer

CREATE OR REPLACE VIEW Q6 (beer, brewery, abv) 
as 
    Select Be.name, Br.name, Be.abv
    
    From Beers Be, Breweries Br, Brewed_by BB
        
    Where 
    (Be.notes LIKE '%barrel%aged%' or
         Be.notes LIKE '%aged%barrel%')

    And 
	Be.id = BB.beer and
    Br.id = BB.brewery

    And Be.abv >= ALL (
						Select BeTemp.abv
							
						from Beers BeTemp, breweries BrTemp, Brewed_by BBTemp
							
						Where 
						BeTemp.notes LIKE '%barrel%aged%' or
						BeTemp.notes LIKE '%aged%barrel%' and
						BeTemp.id = BBTemp.beer and
						BrTemp.id = BBTemp.brewery
					)

	;

		
-- most popular hop

create or replace view Q7(hop)
as
	Select I.name

	From
	Contains C, Ingredients I, Styles S, Beers B1

	Where
	I.itype = 'hop' and
	I.id = C.ingredient 

	Group By
	I.name

	Order By
	Count(C.ingredient) DESC

	Limit 1

;

-- breweries that don't make IPA or Lager or Stout (any variation thereof)

create or replace view Q8(brewery)
as
	Select Br.name 

	From
	Breweries Br

	Where Br.id not in (
		Select BrTemp.id

		From
		Brewed_By BBTemp,
		Breweries BrTemp,
		Beers BeTemp,
		Styles StTemp

		Where
		StTemp.name ~ '(IPA)|(Lager)|(Stout)' and
		StTemp.id = BeTemp.style and 
		BeTemp.id = BBTemp.beer and 
		BrTemp.id = BBTemp.brewery
		
	)
;

-- most commonly used grain in Hazy IPAs

create or replace view Q9(grain)
as

;

-- ingredients not used in any beer

create or replace view Q10(unused)
as
	Select Ing.name

	From Ingredients Ing, Contains Co

	Where Ing.id not in (
							Select IngTemp.id

							From
							Ingredients IngTemp, Contains CoTemp

							Where
							CoTemp.ingredient = IngTemp.id

						)

	Group By
		Ing.name

;
-- min/max abv for a given country
drop type if exists ABVrange cascade;
create type ABVrange as (minABV float, maxABV float);

create or replace function helpermin(_country text) returns float
as $$

Declare

	_minABV float;
	
Begin

	_minABV = 0;

	Select Be.abv into _minABV

	From
	Beers Be, Breweries Br, Brewed_By BB, Locations Lo

	Where
        Lo.country = _country and
        Br.located_in = Lo.id and
        Be.id = BB.beer AND 
        Br.id = BB.brewery AND 
        Be.abv <= ALL (
                        Select Be.abv

                        From
                        beers Be,
                        breweries Br,
                        brewed_by BB,
                        locations Lo

                        Where
                        Lo.country = _country and
                        Br.located_in = Lo.id and
                        Be.id = BB.beer and
                        Br.id = BB.brewery
                    )
        ;

	Return _minABV;

end;
$$
language plpgsql;

create or replace function helpermax(_country text) returns float
as $$

Declare

	_maxABV float;

	
Begin

	_maxABV = 0;

	Select Be.abv into _maxABV

	From
	Beers Be, Breweries Br, Brewed_By BB, Locations Lo

	Where
        Lo.country = _country and
        Br.located_in = Lo.id and
        Be.id = BB.beer AND 
        Br.id = BB.brewery AND 
        Be.abv >= ALL (
                        Select Be.abv

                        From
                        beers Be,
                        breweries Br,
                        brewed_by BB,
                        locations Lo

                        Where
                        Lo.country = _country and
                        Br.located_in = Lo.id and
                        Be.id = BB.beer and
                        Br.id = BB.brewery
                    )
        ;
	Return _maxABV;

end;
$$
language plpgsql;

create or replace function
	Q11(_country text) returns ABVrange
as $$

Declare
    bars integer;
    minABV float;
    maxABV float;

Begin
    minABV = 0;
    maxABV = 0;

	Select * into bars

	From
	Locations Lo

	Where 
	Lo.country = _country;

	If not found then
        Return (minABV,maxABV);

    Else
		minABV := helpermin(_country);
		maxABV := helpermax(_country);

        Return (minABV,maxABV);

    End if;
End;
$$
Language plpgsql;

-- details of beers

drop type if exists BeerData cascade;
create type BeerData as (beer text, brewer text, info text);

create or replace function beers_brewers_info(partial_name text) returns table (beer text, brewer text)
as $$

 
Declare

	brewer text;
	beer text;

Begin

	-- return query 
	Select Be.name, String_agg(Br.name, ' + ' Order by Br.name) into beer, brewer

	From
	Beers Be, Styles St, Brewed_By BB, Breweries Br

	Where
	Br.id = BB.brewery and
	Be.id = BB.beer and
	St.id = Be.style and 
	Be.name ~ partial_name

	-- Group by
	-- Be.id;

	returns table (beer text, brewer text);

End;
$$
language plpgsql;

create or replace function
	Q12(partial_name text) returns setof BeerData
as $$

Declare
	beerID integer;
	beer_n text;
	brewer_n text;
	info text;

Begin
	Select BBInfo.beer, BBInfo.brewer 
	
	from beers_brewers_info (partial_name) BBInfo





	info := '';

	Select BBInfo.name, BBInfo.brewer into beer_n, brewer_n

	From beers_brewers_info (partial_name) BBInfo

	Return next (beer_n, brewer_n, info);

end;
$$
language plpgsql;