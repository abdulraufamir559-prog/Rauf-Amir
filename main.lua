--[[
  @name: Google Gemini text to audio generator
  @author: Abdul Rauf Amir
  @version: 2.1
  @description: Advanced Audio Generator with Custom Folder Download (Share Removed)
]]

require "import"
import "com.androlua.Http"
import "cjson"
import "com.androlua.LuaDialog"
import "android.widget.*"
import "android.view.*"
import "android.content.Context"
import "android.content.Intent"
import "android.net.Uri"
import "android.media.MediaPlayer"
import "android.util.Base64"
import "android.os.*"
import "android.graphics.Typeface"
import "java.io.*"
import "android.text.InputFilter"
import "java.text.SimpleDateFormat"
import "java.util.Date"

local context = activity or service
local mainHandler = Handler(Looper.getMainLooper())

-- Character Limit Fixed to 10,000 for longer scripts
local CHAR_LIMIT = 10000

local VOICE_LIST = {
    "Puck", "Kore", "Charon", "Zephyr", "Fenrir", "Leda",
    "Orus", "Aoede", "Callirrhoe", "Autonoe", "Enceladus", "Iapetus",
    "Umbriel", "Algieba", "Despina", "Erinome", "Algenib", "Rasalgethi",
    "Laomedeia", "Achernar", "Alnilam", "Schedar", "Gacrux", "Pulcherrima"
}

local EMOTIONS = {
    "Natural/Neutral", "Very Happy & Energetic", "Sad & Emotional", 
    "Angry & Loud", "Serious & Professional", "Whispering/Secretive",
    "Excited/Cheer", "Surprised/Shocked", "Tired/Sleepy", 
    "Shy/Romantic", "Heroic/Epic", "Sarcastic/Funny", "Mysterious/Dark"
}

local googleApiKey = ""
local generatedAudioPath = nil
local mediaPlayer = nil

local PREFS_NAME = "Gemini_TTS_Abdul_Rauf"
local prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

function loadSettings()
    googleApiKey = prefs.getString("apikey", "")
end

function saveSettings()
    local editor = prefs.edit()
    editor.putString("apikey", googleApiKey)
    editor.apply()
end

function writeWavHeader(outStream, totalAudioLen)
    local sampleRate = 24000
    local channels = 1
    local bitsPerSample = 16
    local byteRate = sampleRate * channels * (bitsPerSample / 8)
    local blockAlign = channels * (bitsPerSample / 8)
    local totalDataLen = totalAudioLen
    local totalSize = totalDataLen + 36
    local function getBytes(val) return {val & 0xff, (val >> 8) & 0xff, (val >> 16) & 0xff, (val >> 24) & 0xff} end
    local totalSizeB, sampleRateB, byteRateB, dataLenB = getBytes(totalSize), getBytes(sampleRate), getBytes(byteRate), getBytes(totalDataLen)
    local header = {0x52, 0x49, 0x46, 0x46, totalSizeB[1], totalSizeB[2], totalSizeB[3], totalSizeB[4], 0x57, 0x41, 0x56, 0x45, 0x66, 0x6d, 0x74, 0x20, 0x10, 0x00, 0x00, 0x00, 0x01, 0x00, channels & 0xff, (channels >> 8) & 0xff, sampleRateB[1], sampleRateB[2], sampleRateB[3], sampleRateB[4], byteRateB[1], byteRateB[2], byteRateB[3], byteRateB[4], blockAlign & 0xff, (blockAlign >> 8) & 0xff, bitsPerSample & 0xff, (bitsPerSample >> 8) & 0xff, 0x64, 0x61, 0x74, 0x61, dataLenB[1], dataLenB[2], dataLenB[3], dataLenB[4]}
    for i = 1, #header do outStream.write(header[i]) end
end

function copyFile(srcPath, destPath)
    local source = File(srcPath)
    local destination = File(destPath)
    local input = FileInputStream(source)
    local output = FileOutputStream(destination)
    local buffer = byte[1024]
    local length = input.read(buffer)
    while length > 0 do
        output.write(buffer, 0, length)
        length = input.read(buffer)
    end
    input.close()
    output.close()
end

function showExtensionGuide()
    local guideText = [[
WELCOME TO GEMINI TEXT-TO-AUDIO DETAILED GUIDE:

1. API CONFIGURATION:
You must navigate to the 'API' section first. Enter your personal Google Gemini API Key. This key is essential to connect with the cloud servers for high-quality voice generation. Once saved, it will be remembered for your next use.

2. TEXT PREPARATION & CAPACITY:
Input your content in the main text area. We have upgraded the system to handle up to 10,000 characters, allowing you to generate entire stories or long documents in one go.

3. SELECTING EMOTIONS & VOICES:
The AI supports various moods. Choose an emotion like 'Sad & Emotional' or 'Heroic' to change the speech pattern. Select different voice models (Puck, Kore, etc.) to find the perfect match for your text.

4. GENERATION & CONTROLS:
Press 'GENERATE' and wait. Once the processing is complete, use the 'PLAY' button to start listening. If you need to stop, the 'PAUSE' button is now available for your convenience.

5. DOWNLOADING & STORAGE:
Click 'SAVE' to automatically export the .wav file to your Internal Storage inside the 'Download/Gemini text audio generator developed by Abdul Rauf Amir' folder. File Manager Plus and all other managers can instantly access it.
]]
    local views = {}
    local layout = {
        LinearLayout, orientation="vertical", padding="20dp",
        {TextView, text="FULL USER MANUAL", textSize=18, textColor="#2196F3", gravity="center", paddingBottom="10dp", typeface=Typeface.DEFAULT_BOLD},
        {ScrollView, layout_height="350dp", {TextView, text=guideText, textSize=13}},
        {Button, id="closeGuide", text="BACK", layout_width="fill", backgroundColor="#9E9E9E", textColor="#FFFFFF", layout_marginTop="10dp"}
    }
    
    local dlg = LuaDialog(context).setView((loadlayout(layout, views)))
    views.closeGuide.onClick = function() dlg.dismiss() end
    dlg.show()
end

function generateAudio(text, voice, apikey, emotion, generateBtn, playBtn, pauseBtn, downloadBtn, resultLayout)
    local prompts = {
        ["Very Happy & Energetic"] = "Deliver the following text with extreme joy and energy. Text: ",
        ["Sad & Emotional"] = "Deliver the following text with deep sadness and emotion. Text: ",
        ["Angry & Loud"] = "Deliver the following text with intense anger and loudness. Text: ",
        ["Serious & Professional"] = "Deliver the following text professionally. Text: ",
        ["Whispering/Secretive"] = "Deliver the following text in a whisper. Text: ",
        ["Excited/Cheer"] = "Deliver the following text with excitement. Text: ",
        ["Surprised/Shocked"] = "Deliver the following text with shock. Text: ",
        ["Tired/Sleepy"] = "Deliver the following text sounding very tired. Text: ",
        ["Shy/Romantic"] = "Deliver the following text romantically. Text: ",
        ["Heroic/Epic"] = "Deliver the following text heroically. Text: ",
        ["Sarcastic/Funny"] = "Deliver the following text sarcastically. Text: ",
        ["Mysterious/Dark"] = "Deliver the following text mysteriously. Text: "
    }
    local finalPrompt = (prompts[emotion] or "Deliver naturally: ") .. text
    
    local apiUrl = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=" .. apikey
    local requestBody = { contents = {{ parts = {{ text = finalPrompt }} }}, generationConfig = { responseModalities = {"AUDIO"}, speechConfig = { voiceConfig = { prebuiltVoiceConfig = { voiceName = voice } } } } }
    
    Http.post(apiUrl, cjson.encode(requestBody), {["Content-Type"]="application/json"}, function(code, content)
        mainHandler.post(Runnable({run=function()
            if code == 200 then
                local ok, data = pcall(cjson.decode, content)
                if ok and data and data.candidates and data.candidates[1] and data.candidates[1].content and data.candidates[1].content.parts then
                    local parts = data.candidates[1].content.parts
                    local base64Audio = nil
                    for i=1, #parts do
                        if parts[i].inlineData then 
                            base64Audio = parts[i].inlineData.data 
                            break 
                        end
                    end
                    
                    if base64Audio then
                        local audioBytes = Base64.decode(base64Audio, Base64.NO_WRAP)
                        local tempPath = context.getCacheDir().getPath() .. "/tts_temp.wav"
                        local fos = FileOutputStream(File(tempPath))
                        writeWavHeader(fos, #audioBytes)
                        fos.write(audioBytes)
                        fos.close()
                        generatedAudioPath = tempPath
                        
                        resultLayout.setVisibility(View.VISIBLE)
                        playBtn.setEnabled(true)
                        pauseBtn.setEnabled(false)
                        downloadBtn.setEnabled(true)
                        generateBtn.setText("REGENERATE")
                        generateBtn.setEnabled(true)
                        Toast.makeText(context, "Success!", 0).show()
                    else
                        generateBtn.setEnabled(true)
                        generateBtn.setText("GENERATE")
                        Toast.makeText(context, "Audio format data empty", 1).show()
                    end
                else
                    generateBtn.setEnabled(true)
                    generateBtn.setText("GENERATE")
                    Toast.makeText(context, "Response parsing mismatch", 1).show()
                end
            else
                generateBtn.setEnabled(true)
                generateBtn.setText("GENERATE")
                Toast.makeText(context, "API Error: " .. code, 1).show()
            end
        end}))
    end)
end

function showApiSettings()
    local views = {}
    local layout = {
        LinearLayout, orientation="vertical", padding="24dp",
        {TextView, text="API SETTINGS", textSize=18, textColor="#2196F3", gravity="center", paddingBottom="15dp"},
        {EditText, id="apiInput", hint="Paste API Key here...", layout_width="fill", backgroundColor="#F5F5F5", padding="10dp"},
        {Button, id="saveBtn", text="SAVE", layout_width="fill", backgroundColor="#4CAF50", textColor="#FFFFFF", layout_marginTop="10dp"}
    }
    
    local dlg = LuaDialog(context).setView((loadlayout(layout, views)))
    views.apiInput.setText(googleApiKey)
    views.saveBtn.onClick = function()
        googleApiKey = views.apiInput.getText().toString()
        saveSettings()
        dlg.dismiss()
    end
    dlg.show()
end

function showMain()
    loadSettings()
    local views = {}
    local mainLayout = {
        ScrollView, layout_width="fill",
        {
            LinearLayout, orientation="vertical", padding="20dp",
            {TextView, text="Google Gemini text to audio generator", textSize=17, textColor="#2E7D32", gravity="center", typeface=Typeface.DEFAULT_BOLD},
            {TextView, text="By Abdul Rauf Amir", gravity="center", paddingBottom="15dp"},
            {EditText, id="textInput", hint="Enter text...", layout_height="120dp", layout_width="fill", gravity=Gravity.TOP, backgroundColor="#F5F5F5", padding="10dp"},
            {TextView, text="Select Emotion:", layout_marginTop="10dp"},
            {Spinner, id="emotionSpin", layout_width="fill"},
            {TextView, text="Select Voice:", layout_marginTop="5dp"},
            {Spinner, id="voiceSpin", layout_width="fill"},
            {Button, id="generateBtn", text="GENERATE", layout_width="fill", layout_marginTop="15dp", backgroundColor="#2196F3", textColor="#FFFFFF"},
            {LinearLayout, id="resultLayout", visibility=View.GONE, layout_marginTop="10dp",
                {Button, id="playBtn", text="PLAY", layout_weight=1, backgroundColor="#4CAF50", textColor="#FFFFFF"},
                {Button, id="pauseBtn", text="PAUSE", layout_weight=1, backgroundColor="#9E9E9E", textColor="#FFFFFF"},
                {Button, id="downloadBtn", text="SAVE", layout_weight=1, backgroundColor="#FF9800", textColor="#FFFFFF"},
            },
            {LinearLayout, orientation="horizontal", layout_marginTop="20dp", layout_width="fill",
                {Button, id="apiBtn", text="API", layout_weight=1},
                {Button, id="waBtn", text="WHATSAPP", layout_weight=1, backgroundColor="#25D366", textColor="#FFFFFF"},
                {Button, id="guideBtn", text="GUIDE", layout_weight=1, backgroundColor="#FFEB3B", textColor="#000000"},
            },
            {Button, id="exitBtn", text="EXIT", layout_width="fill", backgroundColor="#D32F2F", textColor="#FFFFFF", layout_marginTop="10dp"}
        }
    }
    
    local mainDlg = LuaDialog(context).setView((loadlayout(mainLayout, views)))
    
    views.textInput.setFilters({InputFilter.LengthFilter(CHAR_LIMIT)})
    
    views.emotionSpin.setAdapter(ArrayAdapter(context, android.R.layout.simple_spinner_item, EMOTIONS))
    views.voiceSpin.setAdapter(ArrayAdapter(context, android.R.layout.simple_spinner_item, VOICE_LIST))
    
    views.generateBtn.onClick = function()
        local txt = views.textInput.getText().toString()
        if txt == "" or googleApiKey == "" then Toast.makeText(context, "Required!", 0).show() return end
        views.generateBtn.setText("...")
        views.generateBtn.setEnabled(false)
        generateAudio(txt, VOICE_LIST[views.voiceSpin.getSelectedItemPosition()+1], googleApiKey, EMOTIONS[views.emotionSpin.getSelectedItemPosition()+1], views.generateBtn, views.playBtn, views.pauseBtn, views.downloadBtn, views.resultLayout)
    end
    
    views.playBtn.onClick = function()
        if mediaPlayer then mediaPlayer.start() else
            mediaPlayer = MediaPlayer()
            mediaPlayer.setDataSource(generatedAudioPath)
            mediaPlayer.prepare()
            mediaPlayer.start()
        end
        views.playBtn.setEnabled(false)
        views.pauseBtn.setEnabled(true)
    end
    
    views.pauseBtn.onClick = function()
        if mediaPlayer and mediaPlayer.isPlaying() then
            mediaPlayer.pause()
            views.playBtn.setEnabled(true)
            views.pauseBtn.setEnabled(false)
        end
    end
    
    views.downloadBtn.onClick = function()
        if generatedAudioPath then
            -- Internal Storage / Download folder target paths
            local downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            local customDirName = "Gemini text audio generator developed by Abdul Rauf Amir"
            local targetFolder = File(downloadDir, customDirName)
            
            -- Automaticaly create directory if it doesn't exist
            if not targetFolder.exists() then
                targetFolder.mkdirs()
            end
            
            -- Unique filename generation using timestamp
            local timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss").format(Date())
            local fileName = "Gemini_TTS_" .. timeStamp .. ".wav"
            local destinationFile = File(targetFolder, fileName)
            
            local ok, err = pcall(copyFile, generatedAudioPath, destinationFile.getAbsolutePath())
            if ok then
                Toast.makeText(context, "Saved into Download/" .. customDirName, 1).show()
            else
                Toast.makeText(context, "Save failed: " .. tostring(err), 1).show()
            end
        end
    end
    
    views.apiBtn.onClick = function() showApiSettings() end
    views.guideBtn.onClick = function() showExtensionGuide() end
    views.waBtn.onClick = function()
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://chat.whatsapp.com/B4ptEIk0G5oDpajoujjlZs")))
    end
    
    views.exitBtn.onClick = function() 
        if mediaPlayer then mediaPlayer.release() end
        mainDlg.dismiss()
    end
    
    mainDlg.show()
end

showMain()