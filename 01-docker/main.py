import datetime as dt
import yfinance as yf
import streamlit as st
import asyncio


bitcoin_data = None

async def get_bitcoin_data(start_date: dt.datetime, end_date: dt.datetime, callback=None):
    ticker = 'BTC-USD'
    yf.pdr_override()

    # Read Stock Price Data 
    data = yf.download(ticker, start_date , end_date)
    callback(data)
    return data


def write_bitcoin_data(data):
    global bitcoin_data
    bitcoin_data = data

start_date = dt.datetime.now() - dt.timedelta(days=7)
st.title('Bitcoin Price App')
start_date = st.date_input(
    "start_date_selector",
    value=start_date,
    min_value=dt.datetime.now() - dt.timedelta(days=365),
    max_value=dt.datetime.now(), 
    key=None, 
    help="Select a start date", 
    on_change=None, 
    args=None, 
    format="YYYY/MM/DD", 
    disabled=False, 
    label_visibility="visible")


if start_date is not None:
    is_start_date_selected = True
    
end_date = st.date_input(
    "start_date_selector",
    value=start_date + dt.timedelta(days=7),
    min_value=start_date + dt.timedelta(days=1),
    max_value=start_date + dt.timedelta(days=15), 
    key=None, 
    help="Select an end date (not inclusive)", 
    on_change=None, 
    args=None, 
    format="YYYY/MM/DD", 
    disabled=False, 
    label_visibility="visible")

button_pressed = st.button('Get Data')

if button_pressed:
    bitcoin_data = None
    data_load_state = st.text('Loading data...')
    asyncio.run(get_bitcoin_data(start_date, end_date, callback=write_bitcoin_data))


if bitcoin_data is not None:
    data_load_state.text('Loading data...done!')
    st.write(bitcoin_data)
    st.line_chart(data=bitcoin_data.reset_index(), x='Date', y='Open', width=0, height=0, use_container_width=True)
