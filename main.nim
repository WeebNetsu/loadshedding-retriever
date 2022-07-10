# https://github.com/PolarizedIons/eskom-loadshedding-api
# https://github.com/Cale-Torino/Load_shedding_api

import std/asyncdispatch
from std/httpclient import newAsyncHttpClient, get, body
from std/uri import parseUri, `/`, `?`
from std/json import parseJson, to
from std/htmlparser import parseHtml
from std/xmltree import XmlNode, `$`, innerText
from std/strutils import strip, split, parseInt

# to use css query selectors to work with HTML
import pkg/nimquery

const BASE_URL = parseUri("https://loadshedding.eskom.co.za/LoadShedding")

type
    # {"Disabled":false,"Group":null,"Selected":false,"Text":"Beaufort West","Value":"336"}
    Municipality = object
        Disabled*: bool
        # Group*: int?
        Selected*: bool
        Text*: string
        Value*: string
    MunicipalityData = seq[Municipality]

    # {"id": "1058348", "text": "Balvenie", "Tot": 1402},
    Surburb = object
        id*: string
        text*: string
        # If Tot is 0 then there won't be further data.
        # meaning that if we request a schedule we will get an error from
        # eskom (in html)
        Tot*: int
    SurburbData = object
        Results*: seq[Surburb]
        # total is the amount of surburbs there are, the request
        # can take pageSize, which limits the total amount of results
        Total*: int
    
    Loadshedding = object
        date*: string
        times*: seq[string]
    LoadsheddingData = seq[Loadshedding]

proc getStage(): Future[int] {.async.} =
    const URL = BASE_URL / "GetStatus"

    let 
        client = newAsyncHttpClient()
        res = await client.get(URL)
        body = await res.body

    try:
        # 1 = No load shedding, 2 = Stage 1, 3 = Stage 2, 4 = Stage 3, 5 = Stage 4
        return parseInt(body) - 1
    except:
        # todo do something other than quitting
        echo "Could not get current stage!"
        quit()

proc getMuniciplities(id: uint8 = 9): Future[MunicipalityData] {.async.} =
    #[ 
        1 = Eastern Cape
        2 = Free State
        3 = Gauteng
        4 = KwaZulu-Natal
        5 = Limpopo
        6 = Mpumalanga
        7 = North West
        8 = Northern Cape
        9 = Western Cape
     ]#
    const URL = BASE_URL / "GetMunicipalities"

    let 
        client = newAsyncHttpClient()
        res = await client.get(URL ? {"Id": $id})
        body = await res.body

    return parseJson(body).to(MunicipalityData)

proc getSurburbData(id: uint = 342, pageSize: uint = 1000, pageNum: uint = 1): Future[SurburbData] {.async.} =
    #[ 
        342 - City of Cape Town

        pageSize is 1k, since by default we just want all the data, but if you implement
        pagination, then decrease pageSize and use pageNum instead
        PS. Total in the return data contains the total amount of surburbs 
     ]#
    const URL = BASE_URL / "GetSurburbData"

    let 
        client = newAsyncHttpClient()
        res = await client.get(URL ? {"Id": $id, "pageSize": $pageSize, "pageNum": $pageNum})
        body = await res.body

    # echo parseJson(body).pretty()
    
    return parseJson(body).to(SurburbData)



proc getSchedule(suburbId: uint = 1069151, stage: int = 0, provinceId: uint8 = 9, municipalityTotal: uint = 1): Future[XmlNode] {.async.} =
    #[ 
        1069151 = somerset west mall

        suburb_id	        int	suburbs id	            63591
        stage	            int	stage of loadshedding	2
        province_id	        int	provinces id	        9
        municipality_total	int	municipalitys total	    271
    ]#
    const URL = BASE_URL / "GetScheduleM"
    
    let 
        # <suburb_id>/<stage>/<province_id>/<municipality_total>
        client = newAsyncHttpClient()
        callUrl = URL / $suburbId / $stage / $provinceId / $municipalityTotal
        res = await client.get(callUrl)
        body = await res.body
        actualStage: int = if stage == 0: await getStage() else: stage

    echo callUrl
    # the body contains HTML, not JSON
    return parseHtml(body)

proc generateSchedule(html: XmlNode, days: uint = 5): LoadsheddingData = 
    #[ 
        Days include how many days ahead to return the schedule
    ]#
    let allSchedules: seq[XmlNode] = html.querySelectorAll("div.scheduleDay")

    var 
        curDay: uint = 0
        data: LoadsheddingData = @[]

    for day in allSchedules:
        curDay += 1
        # echo day
        let 
            dayMonth: XmlNode = day.querySelector(".dayMonth")
            dayMonthValue: string = dayMonth.innerText.strip()
        var times: seq[string] = @[]

        for dayTime in day.querySelectorAll("div a"):
            let timeData = dayTime.innerText.strip().split(">")
            times.add(timeData[len(timeData)-1])
        
        data.add(Loadshedding(date: dayMonthValue, times: times))

        if curDay >= days:
            break
    
    return data

proc main(): Future[void] {.async.} =
    let 
        municipalities: MunicipalityData = await getMuniciplities()
        surburbs: SurburbData = await getSurburbData()
        sched = await getSchedule()
        schedules = generateSchedule(sched)

    echo schedules

when isMainModule:
    waitfor main()