#!/usr/bin/env python
# -*- coding: utf-8 -*-
import requests
import json
import sys

if len(sys.argv) < 3:
    print("USAGE: push_result_to_zenodo.py <zenodo_token> <filename>")
    sys.exit(1)

zenodo_token = sys.argv[1]
filename = sys.argv[2]
headers = {"Content-Type": "application/json"}

r = requests.post("https://sandbox.zenodo.org/api/deposit/depositions", params={'access_token': zenodo_token}, json={}, headers=headers)
deposition_id = r.json()['id']

data = {'filename': filename}
files = {'file': open(filename, 'rb')}
r = requests.post("https://sandbox.zenodo.org/api/deposit/depositions/%s/files" % deposition_id, params={'access_token': zenodo_token}, data=data, files=files)

data = {
    'metadata': {
        'title': 'BCdatabaser - '+filename,
        'upload_type': 'dataset',
        'creators': [
            {'name': 'Keller, Alexander', 'affiliation': 'Center for Computational and Theoretical Biology, University of Würzburg, Germany', 'orcid': '0000-0001-5716-3634'},
            {'name': 'Hohlfeld, Sonja C.Y.', 'affiliation': 'Center for Computational and Theoretical Biology, University of Würzburg, Germany'},
            {'name': 'Kolter, Andreas', 'affiliation': 'Systematic Botany, Justus Liebig Universität Giessen, Germany'},
            {'name': 'Schultz, Jörg', 'affiliation': 'Center for Computational and Theoretical Biology, University of Würzburg, Germany'},
            {'name': 'Gemeinholzer, Birgit', 'affiliation': 'Systematic Botany, Justus Liebig Universität Giessen, Germany'},
            {'name': 'Ankenbrand, Markus J.', 'affiliation': 'Center for Computational and Theoretical Biology, University of Würzburg, Germany', 'orcid': '0000-0002-6620-807X'}
        ],
        # TODO use real parameters
        'description':"Parameters: <ul><li>--marker-search-string (ITS2 OR 'internal transcribed spacer 2')</li><li>--taxonomic-range Bellis</li><li>--sequences-per-taxon 2</li>",
        'notes': 'This dataset was automatically created with data from NCBI using the BCdatabaser tool',
        'keywords':['BCdatabaser', 'barcoding', 'ecology', 'database'],
        'references': [
            'Keller et al. (2019) BCdatabaser: on-the-fly reference database creation for (meta-)barcoding. (in preparation) doi:pending https://github.com/molbiodiv/bcdatabaser',
            'eutils: Sayers E. E-utilities Quick Start. 2008 Dec 12 [Updated 2018 Oct 24]. In: Entrez Programming Utilities Help [Internet]. Bethesda (MD): National Center for Biotechnology Information (US); 2010-. Available from: https://www.ncbi.nlm.nih.gov/books/NBK25500/',
            'NCBI::Taxonomy: Förster et al. https://github.com/greatfireball/NCBI-Taxonomy',
            'SeqFilter: Hackl et al. https://github.com/BioInf-Wuerzburg/SeqFilter',
            'dispr: Cofield et al. https://github.com/douglasgscofield/dispr',
            'Krona: Ondov BD, Bergman NH, and Phillippy AM. Interactive metagenomic visualization in a Web browser. BMC Bioinformatics. 2011 Sep 30; 12(1):385.'
        ],
        # TODO use real version
        'version': '0.1.0'
    }
}
r = requests.put('https://sandbox.zenodo.org/api/deposit/depositions/%s' % deposition_id, params={'access_token': zenodo_token}, data=json.dumps(data), headers=headers)
r = requests.post("https://sandbox.zenodo.org/api/deposit/depositions/%s/actions/publish" % deposition_id, params={'access_token': zenodo_token})
print(r.json())