local cmc = ""
local packCount = 0
local magicBack = "http://cloud-3.steamusercontent.com/ugc/1044218919659567154/72AEBC61B3958199DE4389B0A934D68CE53D030B/"
local retryCount = 0
local relatedRetryCount = 0
local maxRetries = 20
local retryWaitFrames = 60
local delayFrames = 6

function onLoad()
    math.randomseed(os.time())
    math.random(); math.random(); math.random()
end

function urlencode (str)
    str = string.gsub (
        str,
        "([^0-9a-zA-Z !'()*._~-])",
        function (c) return string.format ("%%%02X", string.byte(c)) end
    )
    str = string.gsub (str, " ", "+")
    return str
end

function urldecode (str)
    str = string.gsub (str, "+", " ")
    str = string.gsub (str, "%%(%x%x)", function(h) return string.char(tonumber(h,16)) end)
    return str
end

function createCard(name, cardFace, cardBack, player)
    local customCardData = {
        face = cardFace,
        back = cardBack
    }

    local playerSeat = player.getHandTransform()
    local spawnData = {
        type = "CardCustom",
        position = playerSeat.position + (playerSeat.forward * 5 ),
        rotation = vector(playerSeat.rotation.x, (playerSeat.rotation.y + 180) % 360, playerSeat.rotation.z),
        scale = vector(1.5, 1, 1.5)
    }

    local newCard = spawnObject(spawnData)
    newCard.setName(name)
    newCard.setCustomObject(customCardData)

end

function cmcInput(obj, color, input, stillEditing)
    if not stillEditing then
        cmc = string.upper(input)
    end
end

self.createInput({
    input_function="cmcInput", function_owner=self, tooltip="CMC",
    alignment=3, position={-.65,.5,1.3}, height=200, width=400,
    font_size=156, validation=2, label="CMC", value=cmc
})

self.createButton({
    click_function = "submit",
    function_owner = self,
    label          = "Submit",
    position       = {.65, .5, 1.3},
    rotation       = {0, 0, 0},
    width          = 400,
    height         = 200,
    font_size      = 78,
    color          = {0, .5, 0},
    font_color     = {1, 1, 1},
    tooltip        = "Generate card",
})

function submit(obj, color, alt_click)
    if cmc == "" then
        printToAll("Must specify a mana value", {r=255, g=255, b=255})
        return
    end
    retryCount = 0
    relatedRetryCount = 0
    generateCreature(color)
end

function generateCreature(color, set)
    local url = "https://api.scryfall.com/cards/random?q="..urlencode("t:creature cmc:"..cmc)
    url = url..urlencode(" is:booster lang:english game:paper")

    Wait.frames(
        function()
            WebRequest.get(url, function(data) parseCardData(data, color, url) end)
        end,
        delayFrames
    )
end

function parseCardData(data, color, url)
    local status, err = pcall(function () JSON.decode(data.text) end)
    if not status then
        retryCount = retryCount + 1
        if retryCount <= maxRetries then
            Wait.frames(
                function()
                    Wait.frames(
                        function()
                            WebRequest.get(url, function(data) parseCardData(data, color, url) end)
                        end,
                        delayFrames
                    )
                end,
                retryWaitFrames
            )
            return
        else
            printToAll("Ran out of retries", {r=255, g=255, b=255})
            return
        end
    end
    local cardData = JSON.decode(data.text)
    local name = cardData["name"]
    local cardFront
    if cardData["card_faces"] ~= nil and #cardData["card_faces"] > 1 and cardData["card_faces"][1]["image_uris"] ~= nil then
        cardFront = cardData["card_faces"][1]["image_uris"]["normal"]
        local cardBack = cardData["card_faces"][2]["image_uris"]["normal"]
        createCard(name, cardFront, cardBack, Player[color])
        createCard(name, cardFront, magicBack, Player[color])
    else
        if cardData["image_uris"] == nil then
            printToAll("Can't find images for card. Decoded url: "..urldecode(url), {r=255, g=255, b=255})
            for key,value in pairs(cardData) do
                printToAll(key..": "..value, {r=255, g=255, b=255})
            end
        else
            cardFront = cardData["image_uris"]["normal"]
            createCard(name, cardFront, magicBack, Player[color])
        end
    end
    
    --get related cards
    if cardData["all_parts"] then
        for _,part in ipairs(cardData["all_parts"]) do
            if part["component"] == "token" or part["component"] == "meld_result" then
                Wait.frames(
                    function()
                        WebRequest.get(part["uri"], function(data) parseRelatedCardData(data, color, part["uri"]) end)
                    end,
                    delayFrames
                )
            elseif part["component"] == "combo_piece" and string.find(part["type_line"], "Emblem", 1, true) then
                Wait.frames(
                    function()
                        WebRequest.get(part["uri"], function(data) parseRelatedCardData(data, color, part["uri"]) end)
                    end,
                    delayFrames
                )
            end
        end
    end
end

function parseRelatedCardData(data, color, url)
    local status, err = pcall(function () JSON.decode(data.text) end)
    if not status then
        relatedRetryCount = relatedRetryCount + 1
        if relatedRetryCount <= maxRetries then
            Wait.frames(
                function()
                    Wait.frames(
                        function()
                            WebRequest.get(url, function(data) parseRelatedCardData(data, color, url) end)
                        end,
                        delayFrames
                    )
                end,
                retryWaitFrames
            )
            return
        else
            printToAll("ran out of related card retries: "..url, {r=255, g=255, b=255})
            return
        end
    end
    local cardData = JSON.decode(data.text)
    local name = cardData["name"]
    local cardFront
    if cardData["layout"] == "transform" or cardData["layout"] == "modal_dfc" then
        cardFront = cardData["card_faces"][1]["image_uris"]["normal"]
    else
        cardFront = cardData["image_uris"]["normal"]
    end
    createCard(name, cardFront, magicBack, Player[color])
end